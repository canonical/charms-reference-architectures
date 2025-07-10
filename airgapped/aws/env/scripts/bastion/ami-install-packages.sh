#!/usr/bin/env bash


# refresh all packages
apt update
NEEDRESTART_MODE=a apt dist-upgrade -y
apt autoremove -y
apt clean -y
snap refresh

# install required packages
apt install -y curl gnupg ca-certificates retry bash-completion jq

snap install amazon-ssm-agent --classic
snap list amazon-ssm-agent
snap start amazon-ssm-agent

sudo snap install kubectl --channel=1.29/stable --classic
snap install juju --channel=3.6/stable
snap install juju-db --channel=4.4/stable
snap install microk8s --channel=1.29-strict/stable
snap install lxd --channel=6/stable
snap install simplestreams

snap install jhack
snap connect jhack:dot-local-share-juju snapd

# install yq from github, snap confinement issues when reading from /tmp
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq
