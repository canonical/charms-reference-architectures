#!/usr/bin/env bash


# refresh all packages
apt update
NEEDRESTART_MODE=a apt dist-upgrade -y
apt autoremove -y
apt clean -y
snap refresh

# install required packages
apt install -y expect retry jq curl postgresql postgresql-contrib docker.io skopeo

snap install snap-store-proxy
snap install store-admin
snap install amazon-ssm-agent --classic
snap start amazon-ssm-agent

# install yq from github, snap confinement issues when reading from /tmp
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq

# reboot if needed
#if [ -f /var/run/reboot-required ]; then
#    echo 'Reboot required. Rebooting now...'
#    reboot
#fi
