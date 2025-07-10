#!/usr/bin/env bash

# refresh all packages
apt update
NEEDRESTART_MODE=a apt dist-upgrade -y
apt autoremove -y
apt clean -y
snap refresh

# install required packages
apt install curl cpu-checker msr-tools retry bridge-utils dns-root-data dnsmasq-base ubuntu-fan -y

snap install juju-db --channel=4.4/stable
snap install lxd --channel=6/stable

# install required packages
snap install amazon-ssm-agent --classic
snap list amazon-ssm-agent
snap start amazon-ssm-agent
