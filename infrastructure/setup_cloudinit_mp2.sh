#!/bin/bash
# Create cloud-init ISOs for all MP2 Linux servers
# Requires: cloud-localds (apt install cloud-image-utils)
set -e

ISO_DIR="/home/medgm/GNS3/images/QEMU"
ROOT_PASS="Mobitech2024!"

make_iso() {
    local name="$1"
    local ip="$2"
    local gw="$3"
    local hostname="$4"
    local out="$ISO_DIR/mp2-${name}-init.iso"

    tmpdir=$(mktemp -d)

    cat > "$tmpdir/user-data" <<EOF
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
chpasswd:
  list: |
    root:${ROOT_PASS}
  expire: false
ssh_pwauth: true
disable_root: false
ssh_authorized_keys: []
runcmd:
  - systemctl enable ssh
  - systemctl start ssh
EOF

    cat > "$tmpdir/meta-data" <<EOF
instance-id: ${hostname}
local-hostname: ${hostname}
EOF

    cat > "$tmpdir/network-config" <<EOF
version: 2
ethernets:
  ens3:
    addresses: [${ip}]
    gateway4: ${gw}
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
    dhcp4: false
EOF

    cloud-localds --network-config "$tmpdir/network-config" "$out" \
        "$tmpdir/user-data" "$tmpdir/meta-data"
    rm -rf "$tmpdir"
    echo "  Created: $out"
}

echo "=== Creating cloud-init ISOs for MP2 ==="
echo

# DMZ
make_iso "web"      "192.168.50.10/24"  "192.168.50.1"  "srv-web"
make_iso "mail"     "192.168.50.20/24"  "192.168.50.1"  "srv-mail"

# VLAN 10 — Servers
make_iso "ldap"     "192.168.10.10/24"  "192.168.10.1"  "srv-ldap"
make_iso "fichiers" "192.168.10.20/24"  "192.168.10.1"  "srv-fichiers"
make_iso "bdd"      "192.168.10.30/24"  "192.168.10.1"  "srv-bdd"

# Site Agence (example server)
make_iso "agence"   "192.168.60.10/24"  "192.168.60.1"  "srv-agence"

echo
echo "All ISOs created in $ISO_DIR"
echo "Root password for all servers: ${ROOT_PASS}"
