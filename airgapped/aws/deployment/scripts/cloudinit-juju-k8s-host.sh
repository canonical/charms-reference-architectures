#!/usr/bin/env bash

function setup_ssh() {
    mkdir -p /home/ubuntu/.ssh
    cat <<EOF > /home/ubuntu/.ssh/internal
${internal_private_key}
EOF

    chmod 600 /home/ubuntu/.ssh/internal
    chown ubuntu:ubuntu /home/ubuntu/.ssh/internal
}

function setup_microk8s() {
    OCI_REGISTRY="oci-registry.canonical.internal:6000"

    mkdir -p /var/snap/microk8s/current/args/certs.d/"$OCI_REGISTRY/"

    tee /var/snap/microk8s/current/args/certs.d/"$OCI_REGISTRY"/hosts.toml <<EOF
server = "http://$OCI_REGISTRY"
[host."http://$OCI_REGISTRY"]
  capabilities = ["pull", "resolve"]
EOF

    chmod -R 660 /var/snap/microk8s/current/args/certs.d/"$OCI_REGISTRY/"
    chown -R root:snap_microk8s /var/snap/microk8s/current/args/certs.d/"$OCI_REGISTRY/"

    tee /var/snap/microk8s/current/args/certs.d/docker.io/hosts.toml <<EOF
server = "http://$OCI_REGISTRY"
[host."http://$OCI_REGISTRY"]
  capabilities = ["pull", "resolve"]
EOF

    (retry --times 3 --delay 5 -- microk8s stop) || true

    microk8s start
    microk8s status --wait-ready
    microk8s kubectl get nodes --no-headers | awk '{print $1}' | grep -v "$(hostname -s)" | xargs -r -I {} kubectl delete node {}

    microk8s.kubectl rollout status -n kube-system deploy/coredns --watch --timeout=5m
    microk8s.kubectl rollout status -n kube-system deploy/hostpath-provisioner --watch --timeout=5m

    microk8s status --wait-ready
}


setup_ssh
setup_microk8s

usermod -a -G snap_microk8s ubuntu
sudo -u ubuntu bash -c 'mkdir -p ~/.kube'
