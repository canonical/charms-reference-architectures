#!/usr/bin/env bash


function setup_ssh() {
    mkdir -p /home/ubuntu/.ssh

cat <<EOF > /home/ubuntu/.ssh/internal
${internal_private_key}
EOF

    chmod 600 /home/ubuntu/.ssh/internal
    chown ubuntu:ubuntu /home/ubuntu/.ssh/internal
}


setup_ssh
systemctl restart oci-registry.service
