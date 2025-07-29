#!/usr/bin/env bash

# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


# refresh all packages
apt update
NEEDRESTART_MODE=a apt dist-upgrade -y
apt autoremove -y
apt clean -y
snap refresh

# install apt packages
apt install curl cpu-checker msr-tools retry bridge-utils dns-root-data dnsmasq-base ubuntu-fan -y
snap install microk8s --channel=1.29-strict/stable
snap install lxd --channel=6/stable

# install required packages
snap install amazon-ssm-agent --classic
snap list amazon-ssm-agent
snap start amazon-ssm-agent
