#!/usr/bin/env python3
"""
MOBITECH Mini-Projet 2 — GNS3 Topology Builder
Architecture:
  pfSense-Siege (3 NICs: WAN/LAN/DMZ)
    LAN → SW-LAN (VLAN 10 Servers / VLAN 20 Employees / VLAN 30 Admin)
    DMZ → SW-DMZ (Web 50.10 / Mail 50.20)
    WAN → SW-WAN (simulates Internet + VPN link)
  pfSense-Agence (2 NICs: WAN/LAN)
    WAN → SW-WAN
    LAN → SW-Agence
"""

import requests
import sys
import json

API  = "http://localhost:3080/v2"
AUTH = ("admin", "keJinqJlhSgIRriENy6U5gsmbPyzxBqvI5nC4mLIwOzAPyaTPpx2yHGMq2mKlqXx")

# ── helpers ──────────────────────────────────────────────────────────────────

def api(method, path, **kwargs):
    r = requests.request(method, f"{API}{path}", auth=AUTH, **kwargs)
    if r.status_code not in (200, 201, 204):
        print(f"ERROR {r.status_code} {method} {path}: {r.text[:300]}")
        sys.exit(1)
    return r.json() if r.content else {}

def node(proj, name, ntype, x, y, props=None, symbol=None):
    payload = {"name": name, "node_type": ntype, "compute_id": "local", "x": x, "y": y}
    if props:
        payload["properties"] = props
    if symbol:
        payload["symbol"] = symbol
    n = api("POST", f"/projects/{proj}/nodes", json=payload)
    print(f"  + {name} ({ntype}) [{n['node_id'][:8]}]")
    return n

def link(proj, a_id, a_adapter, a_port, b_id, b_adapter, b_port):
    payload = {"nodes": [
        {"node_id": a_id, "adapter_number": a_adapter, "port_number": a_port},
        {"node_id": b_id, "adapter_number": b_adapter, "port_number": b_port},
    ]}
    r = api("POST", f"/projects/{proj}/links", json=payload)
    return r

def drawing(proj, x, y, text, color="#1a237e", fontsize=13):
    svg = (f'<svg width="200" height="28">'
           f'<text x="0" y="20" font-size="{fontsize}" font-weight="bold" '
           f'fill="{color}">{text}</text></svg>')
    api("POST", f"/projects/{proj}/drawings",
        json={"svg": svg, "x": x, "y": y, "locked": False, "rotation": 0})

def switch_ports(proj, sw_id, port_count, vlan_map):
    """Configure ethernet_switch ports with VLAN assignments."""
    ports = [
        {"name": f"Ethernet{i}", "port_number": i,
         "type": "access", "vlan": vlan_map.get(i, 1)}
        for i in range(port_count)
    ]
    api("PUT", f"/projects/{proj}/nodes/{sw_id}", json={"properties": {"ports_mapping": ports}})

# ── Image paths ───────────────────────────────────────────────────────────────

PFSENSE_ISO  = "pfSense-CE-2.7.2-RELEASE-amd64.iso"
DEBIAN_IMG   = "debian-12-genericcloud-amd64.qcow2"
EMPTY_20G    = "empty20G.qcow2"
EMPTY_10G    = "empty10G.qcow2"
QEMU_BIN     = "/usr/bin/qemu-system-x86_64"

# cloud-init ISOs (created by setup_cloudinit_mp2.sh)
CI = {
    "web":      "mp2-web-init.iso",
    "mail":     "mp2-mail-init.iso",
    "ldap":     "mp2-ldap-init.iso",
    "fichiers": "mp2-fichiers-init.iso",
    "bdd":      "mp2-bdd-init.iso",
    "agence":   "mp2-agence-init.iso",
}

def debian_props(ci_iso, ram=1024):
    return {
        "hda_disk_image":       DEBIAN_IMG,
        "hda_disk_interface":   "virtio",
        "cdrom_image":          ci_iso,
        "qemu_path":            QEMU_BIN,
        "adapter_type":         "virtio-net-pci",
        "ram":                  ram,
        "cpus":                 1,
        "adapters":             1,
        "console_type":         "telnet",
    }

def pfsense_props(adapters=3, ram=1024):
    return {
        "hda_disk_image":       EMPTY_20G,
        "hda_disk_interface":   "virtio",
        "cdrom_image":          PFSENSE_ISO,
        "qemu_path":            QEMU_BIN,
        "adapter_type":         "virtio-net-pci",
        "ram":                  ram,
        "cpus":                 1,
        "adapters":             adapters,
        "console_type":         "vnc",
        "options":              "-boot order=cd",
    }

# ── Create / open project ─────────────────────────────────────────────────────

print("=== MOBITECH MP2 Topology Builder ===\n")

proj_list = api("GET", "/projects")
proj = next((p for p in proj_list if p["name"] == "tp-enterprise-mp2"), None)

if proj:
    proj_id = proj["project_id"]
    print(f"Deleting existing project {proj_id}...")
    api("DELETE", f"/projects/{proj_id}")

proj = api("POST", "/projects", json={"name": "tp-enterprise-mp2"})
proj_id = proj["project_id"]
print(f"Project created: {proj_id}")

print()

# ─────────────────────────────────────────────────────────────────────────────
# [1] Switches
# ─────────────────────────────────────────────────────────────────────────────
print("[1] Switches...")

# WAN switch (simulates Internet between two pfSense)
sw_wan = node(proj_id, "SW-WAN", "ethernet_switch", x=0, y=-500)
switch_ports(proj_id, sw_wan["node_id"], 4, {0:1, 1:1, 2:1, 3:1})

# LAN switch (VLAN 10/20/30)
# Port layout:
#  0  = trunk uplink to pfSense LAN (will be untagged VLAN 1 — pfSense does inter-VLAN)
#  1,2,3 = VLAN 10 (servers)
#  4,5,6 = VLAN 20 (employees)
#  7,8   = VLAN 30 (admin)
sw_lan = node(proj_id, "SW-LAN", "ethernet_switch", x=0, y=-100)
vlan_lan = {0:1, 1:10, 2:10, 3:10, 4:20, 5:20, 6:20, 7:30, 8:30}
switch_ports(proj_id, sw_lan["node_id"], 9, vlan_lan)

# DMZ switch
sw_dmz = node(proj_id, "SW-DMZ", "ethernet_switch", x=-600, y=-100)
switch_ports(proj_id, sw_dmz["node_id"], 4, {0:1, 1:1, 2:1, 3:1})

# Agence switch
sw_agence = node(proj_id, "SW-Agence", "ethernet_switch", x=600, y=-100)
switch_ports(proj_id, sw_agence["node_id"], 4, {0:1, 1:1, 2:1, 3:1})

print()

# ─────────────────────────────────────────────────────────────────────────────
# [2] pfSense firewalls
# ─────────────────────────────────────────────────────────────────────────────
print("[2] pfSense firewalls...")

# pfSense Siège: vtnet0=WAN, vtnet1=LAN, vtnet2=DMZ
pfs_siege = node(proj_id, "pfSense-Siege", "qemu", x=0, y=-300,
                 props=pfsense_props(adapters=3, ram=1024))

# pfSense Agence: vtnet0=WAN, vtnet1=LAN
pfs_agence = node(proj_id, "pfSense-Agence", "qemu", x=600, y=-300,
                  props=pfsense_props(adapters=2, ram=512))

print()

# ─────────────────────────────────────────────────────────────────────────────
# [3] Linux servers — Siège
# ─────────────────────────────────────────────────────────────────────────────
print("[3] Linux servers (Siège)...")

# VLAN 10 — Servers
srv_ldap     = node(proj_id, "AD-LDAP",     "qemu", x=-200, y=100, props=debian_props(CI["ldap"],     ram=1024))
srv_fichiers = node(proj_id, "Fichiers",    "qemu", x=  0, y=100, props=debian_props(CI["fichiers"], ram=512))
srv_bdd      = node(proj_id, "BDD-MariaDB", "qemu", x= 200, y=100, props=debian_props(CI["bdd"],      ram=512))

# DMZ
srv_web  = node(proj_id, "Web-Apache",  "qemu", x=-700, y=100, props=debian_props(CI["web"],  ram=512))
srv_mail = node(proj_id, "Mail-Server", "qemu", x=-500, y=100, props=debian_props(CI["mail"], ram=512))

print()

# ─────────────────────────────────────────────────────────────────────────────
# [4] VPCS clients
# ─────────────────────────────────────────────────────────────────────────────
print("[4] VPCS clients...")

# VLAN 20 — Employees (3 representatives)
emp1 = node(proj_id, "Employe-1", "vpcs", x=-100, y=250)
emp2 = node(proj_id, "Employe-2", "vpcs", x=  0, y=250)
emp3 = node(proj_id, "Employe-3", "vpcs", x= 100, y=250)

# VLAN 30 — Admin
admin_pc = node(proj_id, "Admin-PC", "vpcs", x=300, y=100)

# Agence clients
ag1 = node(proj_id, "Agence-PC-1", "vpcs", x=500, y=100)
ag2 = node(proj_id, "Agence-PC-2", "vpcs", x=700, y=100)

print()

# ─────────────────────────────────────────────────────────────────────────────
# [5] Links
# ─────────────────────────────────────────────────────────────────────────────
print("[5] Links...")

P = proj_id

# pfSense-Siege WAN (adapter 0) → SW-WAN port 0
link(P, pfs_siege["node_id"], 0, 0,  sw_wan["node_id"], 0, 0)
print("  pfSense-Siege WAN → SW-WAN:0")

# pfSense-Siege LAN (adapter 1) → SW-LAN port 0
link(P, pfs_siege["node_id"], 1, 0,  sw_lan["node_id"], 0, 0)
print("  pfSense-Siege LAN → SW-LAN:0")

# pfSense-Siege DMZ (adapter 2) → SW-DMZ port 0
link(P, pfs_siege["node_id"], 2, 0,  sw_dmz["node_id"], 0, 0)
print("  pfSense-Siege DMZ → SW-DMZ:0")

# pfSense-Agence WAN (adapter 0) → SW-WAN port 1
link(P, pfs_agence["node_id"], 0, 0,  sw_wan["node_id"], 0, 1)
print("  pfSense-Agence WAN → SW-WAN:1")

# pfSense-Agence LAN (adapter 1) → SW-Agence port 0
link(P, pfs_agence["node_id"], 1, 0,  sw_agence["node_id"], 0, 0)
print("  pfSense-Agence LAN → SW-Agence:0")

# DMZ servers → SW-DMZ
link(P, srv_web["node_id"],  0, 0,  sw_dmz["node_id"], 0, 1)
print("  Web-Apache → SW-DMZ:1")
link(P, srv_mail["node_id"], 0, 0,  sw_dmz["node_id"], 0, 2)
print("  Mail-Server → SW-DMZ:2")

# VLAN 10 servers → SW-LAN ports 1,2,3
link(P, srv_ldap["node_id"],     0, 0,  sw_lan["node_id"], 0, 1)
print("  AD-LDAP → SW-LAN:1 (VLAN10)")
link(P, srv_fichiers["node_id"], 0, 0,  sw_lan["node_id"], 0, 2)
print("  Fichiers → SW-LAN:2 (VLAN10)")
link(P, srv_bdd["node_id"],      0, 0,  sw_lan["node_id"], 0, 3)
print("  BDD-MariaDB → SW-LAN:3 (VLAN10)")

# VLAN 20 employees → SW-LAN ports 4,5,6
link(P, emp1["node_id"], 0, 0,  sw_lan["node_id"], 0, 4)
link(P, emp2["node_id"], 0, 0,  sw_lan["node_id"], 0, 5)
link(P, emp3["node_id"], 0, 0,  sw_lan["node_id"], 0, 6)
print("  Employe-1,2,3 → SW-LAN:4,5,6 (VLAN20)")

# VLAN 30 admin → SW-LAN port 7
link(P, admin_pc["node_id"], 0, 0,  sw_lan["node_id"], 0, 7)
print("  Admin-PC → SW-LAN:7 (VLAN30)")

# Agence clients → SW-Agence
link(P, ag1["node_id"], 0, 0,  sw_agence["node_id"], 0, 1)
link(P, ag2["node_id"], 0, 0,  sw_agence["node_id"], 0, 2)
print("  Agence-PC-1,2 → SW-Agence:1,2")

print()

# ─────────────────────────────────────────────────────────────────────────────
# [6] Labels / drawings
# ─────────────────────────────────────────────────────────────────────────────
print("[6] Labels...")
drawing(P,  -60, -560, "Internet / WAN", "#b71c1c")
drawing(P, -700,  -50, "DMZ  192.168.50.0/24", "#6a1b9a")
drawing(P,  -50,  -50, "LAN  VLANs 10/20/30",  "#1a237e")
drawing(P,  550,  -50, "Site Agence  192.168.60.0/24", "#1b5e20")
drawing(P, -250,  200, "VLAN10 Servers 192.168.10.0/24", "#0d47a1", 11)
drawing(P,  -50,  300, "VLAN20 Employees 192.168.20.0/24 (DHCP)", "#e65100", 11)
drawing(P,  270,  150, "VLAN30 Admin 192.168.30.0/24", "#004d40", 11)

print()
print("=== Done ===")
print(f"Project ID : {proj_id}")
print()
print("IP Plan:")
print("  DMZ:      Web 192.168.50.10 / Mail 192.168.50.20")
print("  VLAN10:   LDAP 192.168.10.10 / Fichiers 192.168.10.20 / BDD 192.168.10.30")
print("  VLAN20:   DHCP 192.168.20.100-230  (gw 192.168.20.1)")
print("  VLAN30:   Admin-PC 192.168.30.10   (gw 192.168.30.1)")
print("  Agence:   192.168.60.x             (gw 192.168.60.1)")
print()
print("Next steps:")
print("  1. Run setup_cloudinit_mp2.sh  → creates cloud-init ISOs for each server")
print("  2. Open GNS3 GUI → start pfSense-Siege → install pfSense via VNC console")
print("  3. Configure pfSense: interfaces, VLANs, DHCP, firewall rules, VPN")
print("  4. Start Debian servers → auto-configured via cloud-init")
print("  5. Run config scripts: configure_ldap.sh, configure_web.sh, configure_security.sh")
