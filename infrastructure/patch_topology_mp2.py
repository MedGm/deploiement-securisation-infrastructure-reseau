#!/usr/bin/env python3
"""
MP2 topology patch — adds missing nodes WITHOUT deleting the project.
Adds: Routeur-FAI, SW-VLAN10/20/30, Switch-Mgmt, AP-WiFi
Rewires: end-devices through access switches, FAI router between SW-WAN and pfSense
"""

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

def add_node(name, ntype, x, y, props=None):
    payload = {"name": name, "node_type": ntype, "compute_id": "local", "x": x, "y": y}
    if props:
        payload["properties"] = props
    n = api("POST", f"/projects/{PROJ}/nodes", json=payload)
    print(f"  + {name} ({ntype}) [{n['node_id'][:8]}]")
    return n["node_id"]

def add_link(a_id, a_adp, a_prt, b_id, b_adp, b_prt, label=""):
    payload = {"nodes": [
        {"node_id": a_id, "adapter_number": a_adp, "port_number": a_prt},
        {"node_id": b_id, "adapter_number": b_adp, "port_number": b_prt},
    ]}
    api("POST", f"/projects/{PROJ}/links", json=payload)
    if label:
        print(f"  ~ {label}")

def del_link(link_id, label=""):
    api("DELETE", f"/projects/{PROJ}/links/{link_id}")
    if label:
        print(f"  - {label}")

def sw_ports(sw_id, count, vlan_map):
    ports = [{"name": f"Ethernet{i}", "port_number": i,
              "type": "access", "vlan": vlan_map.get(i, 1)}
             for i in range(count)]
    api("PUT", f"/projects/{PROJ}/nodes/{sw_id}", json={"properties": {"ports_mapping": ports}})

# ── Known IDs from project file ───────────────────────────────────────────────
SW_WAN     = "2647806e-f4b4-4b05-a057-ab1296d512c3"
SW_LAN     = "ddcf247b-7f1f-49a6-8976-601455c7de1b"
SW_DMZ     = "6f706951-20c1-41ca-914e-bacfdd0d74e8"
SW_AGENCE  = "8ce7b511-d33a-4f76-a290-87fc1d9725f6"
PFS_SIEGE  = "4d271d0a-deea-4609-8274-641b0b8a5be6"
PFS_AGENCE = "6594c455-a860-495f-9772-9a076cd99849"
AD_LDAP    = "a8c8714a-056b-493d-a68f-4104397f19e0"
FICHIERS   = "b5ba2386-b7e7-4a04-8030-1e85c8ac98e4"
BDD        = "36fdca21-c249-44b2-ac74-c8378d6e0f69"
WEB        = "102b29d2-c09c-488c-816a-677537b0a579"
MAIL       = "64831162-56b2-4ffa-8726-6cbccc2da09b"
EMP1       = "73389ffc-e05e-4914-af7c-d9df758bad94"
EMP2       = "b1143b92-196c-4748-9d40-1f58af1ff962"
EMP3       = "f54a4885-51db-4977-803b-27a34753d172"
ADMIN_PC   = "295ff8b7-199b-47ed-b756-70ca50878c83"
AG_PC1     = "0965d7c3-4735-47f4-907d-67c3da25a8b1"
AG_PC2     = "1441b190-7b02-4fb4-9cfa-84dba99b91d6"

# Links to delete (rewiring)
LINK_PFS_WAN   = "2dba5bb1-5427-48ba-b2b4-bcb449fdb16d"  # pfSense-Siege WAN ↔ SW-WAN
LINK_LDAP      = "c7244e9c-abaf-4817-881e-c13a2f2c0359"  # AD-LDAP ↔ SW-LAN p1
LINK_FICHIERS  = "6bda2f57-0bb5-44eb-81d6-f9037be5854b"  # Fichiers ↔ SW-LAN p2
LINK_BDD       = "65ba0bf5-5871-4465-b061-b8fbd7089743"  # BDD ↔ SW-LAN p3
LINK_EMP1      = "d948cee2-3acb-4f49-b435-3d3b18c827e6"  # Employe-1 ↔ SW-LAN p4
LINK_EMP2      = "44c31a5b-6f6f-4d1f-a360-4f1725b21d9f"  # Employe-2 ↔ SW-LAN p5
LINK_EMP3      = "6ba00c93-299c-4b96-8fe5-97187f023497"  # Employe-3 ↔ SW-LAN p6
LINK_ADMIN     = "dff5d7a7-970a-4f69-83fb-9fbe5b70ac43"  # Admin-PC ↔ SW-LAN p7

print("=== MP2 Topology Patch ===\n")
api("POST", f"/projects/{PROJ}/open")

# ── Step 1: Delete links to rewire ───────────────────────────────────────────
print("[1] Removing links to rewire...")
del_link(LINK_PFS_WAN,  "pfSense-Siege WAN ↔ SW-WAN")
del_link(LINK_LDAP,     "AD-LDAP ↔ SW-LAN")
del_link(LINK_FICHIERS, "Fichiers ↔ SW-LAN")
del_link(LINK_BDD,      "BDD ↔ SW-LAN")
del_link(LINK_EMP1,     "Employe-1 ↔ SW-LAN")
del_link(LINK_EMP2,     "Employe-2 ↔ SW-LAN")
del_link(LINK_EMP3,     "Employe-3 ↔ SW-LAN")
del_link(LINK_ADMIN,    "Admin-PC ↔ SW-LAN")
print()

# ── Step 2: Add new nodes ─────────────────────────────────────────────────────
print("[2] Adding new nodes...")

# Routeur-FAI between SW-WAN (y=-492) and pfSense (y=-301)
FAI = add_node("Routeur-FAI", "ethernet_switch", x=-2, y=-410)
sw_ports(FAI, 3, {0:1, 1:1, 2:1})

# Access switches between SW-LAN (y=-96) and end devices (y≈244)
SW10 = add_node("SW-VLAN10", "ethernet_switch", x=-365, y=105)
SW20 = add_node("SW-VLAN20", "ethernet_switch", x= -23, y=105)
SW30 = add_node("SW-VLAN30", "ethernet_switch", x= 285, y=105)

sw_ports(SW10, 5, {0:10, 1:10, 2:10, 3:10, 4:10})
sw_ports(SW20, 5, {0:20, 1:20, 2:20, 3:20, 4:20})
sw_ports(SW30, 5, {0:30, 1:30, 2:30, 3:30, 4:30})

# VLAN30 extra nodes
SW_MGMT = add_node("Switch-Mgmt", "vpcs", x=185, y=340)
AP_WIFI = add_node("AP-WiFi",     "vpcs", x=385, y=340)

print()

# ── Step 3: Rewire SW-LAN ports (update VLAN map) ────────────────────────────
print("[3] Updating SW-LAN port VLANs...")
# port 0: pfSense LAN (keep, VLAN 1 trunk)
# port 1: to SW-VLAN10  → VLAN 10
# port 2: to SW-VLAN20  → VLAN 20
# port 3: to SW-VLAN30  → VLAN 30
sw_ports(SW_LAN, 4, {0:1, 1:10, 2:20, 3:30})
print("  SW-LAN ports reconfigured: p0=trunk, p1=VLAN10, p2=VLAN20, p3=VLAN30")
print()

# ── Step 4: Create new links ──────────────────────────────────────────────────
print("[4] Creating new links...")

# Routeur-FAI chain: SW-WAN p2 → FAI p0 → pfSense-Siege WAN (adapter 0)
add_link(SW_WAN,    0, 2,  FAI,      0, 0, "SW-WAN p2 → Routeur-FAI p0")
add_link(FAI,       0, 1,  PFS_SIEGE,0, 0, "Routeur-FAI p1 → pfSense-Siege WAN")

# SW-LAN → access switches
add_link(SW_LAN, 0, 1,  SW10, 0, 0, "SW-LAN p1 → SW-VLAN10 p0")
add_link(SW_LAN, 0, 2,  SW20, 0, 0, "SW-LAN p2 → SW-VLAN20 p0")
add_link(SW_LAN, 0, 3,  SW30, 0, 0, "SW-LAN p3 → SW-VLAN30 p0")

# VLAN10 devices → SW-VLAN10
add_link(AD_LDAP,  0, 0,  SW10, 0, 1, "AD-LDAP → SW-VLAN10 p1")
add_link(FICHIERS, 0, 0,  SW10, 0, 2, "Fichiers → SW-VLAN10 p2")
add_link(BDD,      0, 0,  SW10, 0, 3, "BDD-MariaDB → SW-VLAN10 p3")

# VLAN20 devices → SW-VLAN20
add_link(EMP1, 0, 0,  SW20, 0, 1, "Employe-1 → SW-VLAN20 p1")
add_link(EMP2, 0, 0,  SW20, 0, 2, "Employe-2 → SW-VLAN20 p2")
add_link(EMP3, 0, 0,  SW20, 0, 3, "Employe-3 → SW-VLAN20 p3")

# VLAN30 devices → SW-VLAN30
add_link(ADMIN_PC, 0, 0,  SW30, 0, 1, "Admin-PC → SW-VLAN30 p1")
add_link(SW_MGMT,  0, 0,  SW30, 0, 2, "Switch-Mgmt → SW-VLAN30 p2")
add_link(AP_WIFI,  0, 0,  SW30, 0, 3, "AP-WiFi → SW-VLAN30 p3")

print()
print("=== Patch complete ===")
print("Refresh GNS3 GUI (View → Reload) to see changes.")
