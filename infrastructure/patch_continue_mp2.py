#!/usr/bin/env python3
"""Continuation of MP2 patch — fixes SW-LAN VLANs and creates all remaining links."""

import requests, sys

API  = "http://localhost:3080/v2"
AUTH = ("admin", "keJinqJlhSgIRriENy6U5gsmbPyzxBqvI5nC4mLIwOzAPyaTPpx2yHGMq2mKlqXx")
PROJ = "76e70761-bfee-4e1e-997c-4ea5a2587b31"

def api(method, path, **kwargs):
    r = requests.request(method, f"{API}{path}", auth=AUTH, **kwargs)
    if r.status_code not in (200, 201, 204):
        print(f"ERROR {r.status_code} {method} {path}: {r.text[:300]}")
        sys.exit(1)
    return r.json() if r.content else {}

def add_link(a_id, a_adp, a_prt, b_id, b_adp, b_prt, label=""):
    payload = {"nodes": [
        {"node_id": a_id, "adapter_number": a_adp, "port_number": a_prt},
        {"node_id": b_id, "adapter_number": b_adp, "port_number": b_prt},
    ]}
    api("POST", f"/projects/{PROJ}/links", json=payload)
    if label:
        print(f"  ~ {label}")

def sw_ports(sw_id, count, vlan_map):
    ports = [{"name": f"Ethernet{i}", "port_number": i,
              "type": "access", "vlan": vlan_map.get(i, 1)}
             for i in range(count)]
    api("PUT", f"/projects/{PROJ}/nodes/{sw_id}", json={"properties": {"ports_mapping": ports}})

# Node IDs
SW_WAN    = "2647806e-f4b4-4b05-a057-ab1296d512c3"
SW_LAN    = "ddcf247b-7f1f-49a6-8976-601455c7de1b"
PFS_SIEGE = "4d271d0a-deea-4609-8274-641b0b8a5be6"
AD_LDAP   = "a8c8714a-056b-493d-a68f-4104397f19e0"
FICHIERS  = "b5ba2386-b7e7-4a04-8030-1e85c8ac98e4"
BDD       = "36fdca21-c249-44b2-ac74-c8378d6e0f69"
EMP1      = "73389ffc-e05e-4914-af7c-d9df758bad94"
EMP2      = "b1143b92-196c-4748-9d40-1f58af1ff962"
EMP3      = "f54a4885-51db-4977-803b-27a34753d172"
ADMIN_PC  = "295ff8b7-199b-47ed-b756-70ca50878c83"
FAI       = "4aef3d4b-dea4-4727-bc6f-0d9adcfae78c"
SW10      = "5b49c8e2-cd6b-4e86-9f1a-131c18be784c"
SW20      = "d65ae36f-bdb6-43b0-9459-8a66d8dc9a47"
SW30      = "30cbb49a-23ae-4a94-aaf0-cba5a428aa54"
SW_MGMT   = "38893e52-4796-4f93-8040-2abbf60b4725"
AP_WIFI   = "251c6526-47e7-4f5e-8a0e-6713e7ddedf1"

# Only remaining link on SW-LAN
LINK_PFS_LAN = "56f25e77-d25a-4e66-9347-382ddc59ba3f"

print("=== MP2 Patch Continuation ===\n")
api("POST", f"/projects/{PROJ}/open")

# Step 1: Remove pfSense LAN link so SW-LAN is fully disconnected
print("[1] Removing pfSense-Siege LAN ↔ SW-LAN (to allow VLAN edit)...")
api("DELETE", f"/projects/{PROJ}/links/{LINK_PFS_LAN}")
print("  - pfSense-Siege LAN ↔ SW-LAN p0")

# Step 2: Update SW-LAN VLAN map (now fully disconnected)
print("\n[2] Updating SW-LAN VLANs...")
sw_ports(SW_LAN, 4, {0:1, 1:10, 2:20, 3:30})
print("  p0=VLAN1(trunk→pfSense) / p1=VLAN10(→SW-VLAN10) / p2=VLAN20(→SW-VLAN20) / p3=VLAN30(→SW-VLAN30)")

# Step 3: All new links
print("\n[3] Creating links...")

# Routeur-FAI chain
add_link(SW_WAN,    0, 2,  FAI,      0, 0, "SW-WAN p2 → Routeur-FAI p0")
add_link(FAI,       0, 1,  PFS_SIEGE,0, 0, "Routeur-FAI p1 → pfSense-Siege WAN (adapter0)")

# pfSense LAN reconnect
add_link(PFS_SIEGE, 1, 0,  SW_LAN,   0, 0, "pfSense-Siege LAN → SW-LAN p0")

# SW-LAN → access switches
add_link(SW_LAN, 0, 1,  SW10, 0, 0, "SW-LAN p1 → SW-VLAN10 p0")
add_link(SW_LAN, 0, 2,  SW20, 0, 0, "SW-LAN p2 → SW-VLAN20 p0")
add_link(SW_LAN, 0, 3,  SW30, 0, 0, "SW-LAN p3 → SW-VLAN30 p0")

# VLAN10 devices
add_link(AD_LDAP,  0, 0,  SW10, 0, 1, "AD-LDAP → SW-VLAN10 p1")
add_link(FICHIERS, 0, 0,  SW10, 0, 2, "Fichiers → SW-VLAN10 p2")
add_link(BDD,      0, 0,  SW10, 0, 3, "BDD-MariaDB → SW-VLAN10 p3")

# VLAN20 devices
add_link(EMP1, 0, 0,  SW20, 0, 1, "Employe-1 → SW-VLAN20 p1")
add_link(EMP2, 0, 0,  SW20, 0, 2, "Employe-2 → SW-VLAN20 p2")
add_link(EMP3, 0, 0,  SW20, 0, 3, "Employe-3 → SW-VLAN20 p3")

# VLAN30 devices
add_link(ADMIN_PC, 0, 0,  SW30, 0, 1, "Admin-PC → SW-VLAN30 p1")
add_link(SW_MGMT,  0, 0,  SW30, 0, 2, "Switch-Mgmt → SW-VLAN30 p2")
add_link(AP_WIFI,  0, 0,  SW30, 0, 3, "AP-WiFi → SW-VLAN30 p3")

print("\n=== Done. Refresh GNS3 GUI ===")
