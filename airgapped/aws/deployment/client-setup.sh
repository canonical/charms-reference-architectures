#!/usr/bin/env bash

# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


echo "Installing required dependencies..."
if [[ "$(uname -s)" == "Darwin" ]]; then
    wireguard_config_path="/usr/local/etc/wireguard"
    brew install wireguard-tools
elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID}" == ubuntu ]]; then
        wireguard_config_path="/etc/wireguard"
        sudo apt-get install wireguard
    else
        echo "Error: unsupported distro ${NAME}" >&2
        exit 1
    fi
else
    echo "Error: Unknown or unsupported OS" >&2
    exit 1
fi


echo -e "\nGenerating key pair..."
wg genkey | tee client.key | wg pubkey > client.pub
vpn_client_public_key=$(cat client.pub)
vpn_client_private_key=$(cat client.key)

echo -e "\nVPN Client public key - paste it into the VPN server's /etc/wireguard/wg0.conf in the Peer/PublicKey section"
echo -e "(If you're using terraform, put it in the variable 'vpn_client_public_key': "
echo "${vpn_client_public_key}"

echo -e "\n"

read -r -p "Enter the VPN Server instance's Public IP: " vpn_server_public_ip
echo "${vpn_server_public_ip}"

echo -e "\n"

read -r -p "Enter the VPN Server key's public key (sudo cat /etc/wireguard/server.pub): " vpn_server_public_key
echo "${vpn_server_public_key}"

cat <<EOF > ${wireguard_config_path}/client.conf
[Interface]
PrivateKey = ${vpn_client_private_key}
Address = 10.8.0.2/24

[Peer]
PublicKey = ${vpn_server_public_key}
Endpoint = ${vpn_server_public_ip}:51820
AllowedIPs = 10.0.0.0/16      # VPC CIDR
PersistentKeepalive = 25
EOF

echo -e "\nStarting the VPN at "10.8.0.1"... (sudo wg-quick up client)"
sudo wg-quick down client || true
sudo wg-quick up client

echo -e "\nVPN started"
