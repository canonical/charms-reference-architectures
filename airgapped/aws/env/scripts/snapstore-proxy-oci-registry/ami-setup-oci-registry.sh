#!/usr/bin/env bash

# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


OCI_REGISTRY="oci-registry.canonical.internal"


function start_docker() {
    systemctl enable docker
    systemctl start docker
}

function create_oci_registry() {
    OCI_REGISTRY="/opt/oci-registry"
    mkdir -p "${OCI_REGISTRY}"

    docker run -d \
       --name oci-registry \
       -p 6000:5000 \
       -v "${OCI_REGISTRY}":/var/lib/registry \
       registry:2
}

function start_registry_on_boot() {
cat > /etc/systemd/system/oci-registry.service << EOF
[Unit]
Description=OCI Registry Container
After=docker.service
Requires=docker.service

[Service]
Restart=always
Type=simple
ExecStartPre=-/usr/bin/docker rm oci-registry
ExecStart=/usr/bin/docker run \
  --name oci-registry \
  -p 6000:5000 \
  -v /opt/oci-registry:/var/lib/registry \
  registry:2
ExecStop=/usr/bin/docker stop oci-registry

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable oci-registry.service
    systemctl daemon-reexec
    systemctl daemon-reload
}


# register the OCI registry in the snap-store-proxy
echo "127.0.0.1 oci-registry.canonical.internal" | tee -a /etc/hosts

start_docker
create_oci_registry
start_registry_on_boot

snap-store-proxy config proxy.oci-registry.domain="http://oci-registry.canonical.internal:6000"
sed -i '/127\.0\.0\.1\s\+oci-registry\.canonical\.internal/d' /etc/hosts
