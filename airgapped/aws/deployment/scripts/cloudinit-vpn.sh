#!/usr/bin/env bash


apt update
NEEDRESTART_MODE=a apt dist-upgrade -y
apt autoremove -y
apt clean -y
snap refresh

# Pre-seed debconf answers BEFORE installing iptables-persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections

apt install wireguard iptables-persistent -y

umask 077
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub

cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(cat /etc/wireguard/server.key)
Address = 10.8.0.1/24
ListenPort = 51820

# Enable NAT (for VPN -> VPC routing)
PostUp = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ens5 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o ens5 -j MASQUERADE

# Client section - insert actual pub key later
[Peer]
PublicKey = ${vpn_client_public_key}
AllowedIPs = 10.8.0.2/32
EOF

# enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
