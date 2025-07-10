#!/usr/bin/env bash


JUJU_VERSION="3.6.5"

HOME="/root"
TMP_DIR="${HOME}"/ami/tmp   # necessary because store-admin doesn't work with the /tmp dir

function _retrieve_k8s_charms_oic_def() {
    CHARMS_TARBALLS_DIR="/var/snap/snap-store-proxy/common/charms-to-push/"
    TMP_CHARMS_DIR="${TMP_DIR}/charms"

    rm -rf "${TMP_CHARMS_DIR}" && mkdir -p "${TMP_CHARMS_DIR}"

    # Extract each top-level tarball into /tmp/charms/<base>
    find "${CHARMS_TARBALLS_DIR}" -maxdepth 1 -type f -name "*.tar.gz" | while read -r top_tar; do
        base=$(basename "${top_tar}" .tar.gz)
        mkdir -p "${TMP_CHARMS_DIR}/${base}"
        tar -xzf "${top_tar}" -C "${TMP_CHARMS_DIR}/${base}"
    done

    # Recursively extract all nested charm tarballs inside each extracted root
    find "${TMP_CHARMS_DIR}" -type f -name '*.tar.gz' | while read -r charm_tar; do
        charm_dir="${charm_tar%.tar.gz}"
        mkdir -p "${charm_dir}"
        tar -xzf "${charm_tar}" -C "${charm_dir}"
    done

    # Collect all OCI resource definitions for k8s charms
    find "${TMP_CHARMS_DIR}" -type f -path "*/resources/*" -name "*_*" -print0 | xargs -0 jq -s '.'
}

function export_bundles() {
    RESOURCES="/tmp/resources.yaml"
    TARGET_DIR="/var/snap/snap-store-proxy/common/charms-to-push/"

    bundles_count=$(yq '.bundles | length' "${RESOURCES}")
    for i in $(seq 0 $((bundles_count - 1))); do
        name=$(yq -r ".bundles[$i].name" "${RESOURCES}")
        channel=$(yq -r ".bundles[$i].channel" "${RESOURCES}")
        series=$(yq -r ".bundles[$i].series" "${RESOURCES}")

        store-admin export bundle "${name}" --channel="${channel}" --series="${series}"

        mv "${HOME}"/snap/store-admin/common/export/"${name}"-*.tar.gz "${TARGET_DIR}"
    done
}

function export_charms() {
    RESOURCES="/tmp/resources.yaml"
    TARGET_DIR="/var/snap/snap-store-proxy/common/charms-to-push/"

    mkdir -p "${TMP_DIR}"

    # export the user-provided charms
    yq -P '{"applications": .applications}' "${RESOURCES}" > "${TMP_DIR}"/charms.yaml
    store-admin export charms "${TMP_DIR}"/charms.yaml

    mv "${HOME}"/snap/store-admin/common/export/charms-export-*.tar.gz "${TARGET_DIR}"
}

function export_snaps() {
    RESOURCES="/tmp/resources.yaml"
    TARGET_DIR="/var/snap/snap-store-proxy/common/snaps-to-push/"

    # export mandatory snaps
    store-admin export snaps snapd core core18 core20 core22 core24
    store-admin export snaps microk8s --channel=1.29-strict/stable

    # export user provided snaps (as used by the charms)
    yq -P '{"packages": .packages}' "${RESOURCES}" > "${TMP_DIR}"/snaps.yaml
    store-admin export snaps --from-yaml "${TMP_DIR}"/snaps.yaml

    mv "${HOME}"/snap/store-admin/common/export/*.tar.gz "${TARGET_DIR}"
}


function copy_remote_images_to_local_registry() {
    _retrieve_k8s_charms_oic_def | jq -c '.[]' | while read -r item; do
        image=$(echo "${item}" | jq -r '.ImageName')
        user=$(echo "${item}" | jq -r '.Username')
        pwd=$(echo "${item}" | jq -r '.Password')

        # Extract domain and full path properly
        domain=${image%%/*}
        full_path=${image#"$domain/"}  # Everything after domain

        # Separate digest from path
        if [[ "${full_path}" == *"@"* ]]; then
            repo_path=$(echo "${full_path}" | cut -d'@' -f1)
            index_digest=$(echo "${full_path}" | cut -d'@' -f2)
        else
            repo_path="${full_path}"
            index_digest=""
        fi

        echo "Resolve real image manifest for: ${image}"
        manifest_json=$(skopeo inspect --raw --creds "${user}:${pwd}" docker://"${image}" 2>/dev/null)

        resolved_digest=$(echo "${manifest_json}" | jq -r '.manifests[0].digest' 2>/dev/null)
        if [[ "${resolved_digest}" == "null" || -z "${resolved_digest}" ]]; then
            echo "No manifest list found. Assuming single manifest: ${index_digest}"
            resolved_digest="${index_digest}"
        else
            echo "Resolved platform-specific digest: ${resolved_digest}"
        fi

        # Keep the full original repository path
        resolved_image="docker://${domain}/${repo_path}@${resolved_digest}"
        dest_image="docker://oci-registry.canonical.internal:6000/${repo_path}"

        echo "Mirroring ${resolved_image} -> ${dest_image}"

        # Copy the image directly to destination with tag
        skopeo copy --src-creds "${user}:${pwd}" --dest-tls-verify=false "${resolved_image}" "${dest_image}"

        # Now try to add the digest reference using the same image we just pushed
        dest_with_digest="${dest_image}@${resolved_digest}"
        skopeo copy --src-tls-verify=false --dest-tls-verify=false "${dest_image}:latest" "${dest_with_digest}"

        echo "Successfully mirrored ${repo_path}"
        echo "- Source image: ${resolved_image}"
        echo "- Destination image: ${dest_image}"
    done

    # base images for charms
    docker pull jujusolutions/jujud-operator:${JUJU_VERSION}
    docker pull jujusolutions/charm-base:ubuntu-22.04
    docker pull jujusolutions/charm-base:ubuntu-24.04
    docker pull busybox:1.28.4

    docker tag jujusolutions/jujud-operator:${JUJU_VERSION} oci-registry.canonical.internal:6000/jujusolutions/jujud-operator:${JUJU_VERSION}
    docker tag jujusolutions/charm-base:ubuntu-22.04 oci-registry.canonical.internal:6000/jujusolutions/charm-base:ubuntu-22.04
    docker tag jujusolutions/charm-base:ubuntu-24.04 oci-registry.canonical.internal:6000/jujusolutions/charm-base:ubuntu-24.04
    docker tag busybox:1.28.4 oci-registry.canonical.internal:6000/library/busybox:1.28.4

    # push to local OCI registry
    docker push oci-registry.canonical.internal:6000/jujusolutions/jujud-operator:${JUJU_VERSION}
    docker push oci-registry.canonical.internal:6000/jujusolutions/charm-base:ubuntu-22.04
    docker push oci-registry.canonical.internal:6000/jujusolutions/charm-base:ubuntu-22.04
    docker push oci-registry.canonical.internal:6000/library/busybox:1.28.4
}


function push_resources() {
    # push bundles
    RESOURCES="/tmp/resources.yaml"
    TARGET_DIR="/var/snap/snap-store-proxy/common/charms-to-push"

    snap-store-proxy enable-airgap-mode
    snap restart snap-store-proxy

    bundles_count=$(yq '.bundles | length' "${RESOURCES}")
    for i in $(seq 0 $((bundles_count - 1))); do
        name=$(yq -r ".bundles[$i].name" "${RESOURCES}")
        snap-store-proxy push-charm-bundle "${TARGET_DIR}/${name}"-*
    done

    # push charms
    snap-store-proxy push-charms "${TARGET_DIR}"/charms-export-*

    # push snaps
    TARGET_DIR="/var/snap/snap-store-proxy/common/snaps-to-push"
    for file in "${TARGET_DIR}"/*.tar.gz; do
        snap-store-proxy push-snap "${file}" || true
    done

    snap-store-proxy list-pushed-snaps
}


echo "127.0.0.1 oci-registry.canonical.internal" | tee -a /etc/hosts

export_bundles
export_charms
export_snaps
copy_remote_images_to_local_registry
push_resources

sed -i '/127\.0\.0\.1\s\+oci-registry\.canonical\.internal/d' /etc/hosts
