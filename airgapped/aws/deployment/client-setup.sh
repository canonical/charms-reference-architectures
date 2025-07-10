#!/usr/bin/env bash

echo "Installing required dependencies..."
brew install wireguard-tools

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

cat <<EOF > /usr/local/etc/wireguard/client.conf
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
