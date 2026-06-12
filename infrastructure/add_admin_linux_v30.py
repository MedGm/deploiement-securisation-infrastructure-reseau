#!/usr/bin/env python3
"""Add a small Debian admin client to VLAN 30 in the MP2 GNS3 project.

This script talks to the local GNS3 API on localhost:3080 and creates a
new QEMU node connected to SW-VLAN30. It is intended to provide a real
Linux SSH client for the demo, since the existing Admin-PC is a VPCS.
"""

import sys
import requests

API = "http://localhost:3080/v2"
AUTH = ("admin", "keJinqJlhSgIRriENy6U5gsmbPyzxBqvI5nC4mLIwOzAPyaTPpx2yHGMq2mKlqXx")
PROJECT_NAME = "infra"
NODE_NAME = "Admin-Linux"
ISO_NAME = "mp2-adminlinux-init.iso"
DEBIAN_IMG = "debian-12-genericcloud-amd64.qcow2"
QEMU_BIN = "/usr/bin/qemu-system-x86_64"


def api(method, path, **kwargs):
    response = requests.request(method, f"{API}{path}", auth=AUTH, **kwargs)
    if response.status_code not in (200, 201, 204):
        print(f"ERROR {response.status_code} {method} {path}: {response.text[:300]}")
        sys.exit(1)
    return response.json() if response.content else {}


def find_project(name):
    for project in api("GET", "/projects"):
        if project.get("name") == name:
            return project
    return None


def find_node(project_id, node_name):
    for node in api("GET", f"/projects/{project_id}/nodes"):
        if node.get("name") == node_name:
            return node
    return None


def create_node(project_id):
    payload = {
        "name": NODE_NAME,
        "node_type": "qemu",
        "compute_id": "local",
        "x": 420,
        "y": 120,
        "properties": {
            "hda_disk_image": DEBIAN_IMG,
            "hda_disk_interface": "virtio",
            "cdrom_image": ISO_NAME,
            "qemu_path": QEMU_BIN,
            "adapter_type": "virtio-net-pci",
            "ram": 512,
            "cpus": 1,
            "adapters": 1,
            "console_type": "telnet",
        },
    }
    node = api("POST", f"/projects/{project_id}/nodes", json=payload)
    print(f"Created node {NODE_NAME}: {node['node_id'][:8]}")
    return node


def create_link(project_id, admin_node_id, sw30_node_id):
    payload = {
        "nodes": [
            {"node_id": admin_node_id, "adapter_number": 0, "port_number": 0},
            {"node_id": sw30_node_id, "adapter_number": 0, "port_number": 4},
        ]
    }
    api("POST", f"/projects/{project_id}/links", json=payload)
    print("Linked Admin-Linux to SW-VLAN30 port 4")


def set_ports(project_id, sw30_node_id):
    ports = [
        {"name": f"Ethernet{i}", "port_number": i, "type": "access", "vlan": 30}
        for i in range(5)
    ]
    api("PUT", f"/projects/{project_id}/nodes/{sw30_node_id}", json={"properties": {"ports_mapping": ports}})


if __name__ == "__main__":
    print("=== Add Admin Linux VLAN30 ===")
    project = find_project(PROJECT_NAME)
    if not project:
        print(f"Project {PROJECT_NAME} not found")
        sys.exit(1)

    project_id = project["project_id"]
    api("POST", f"/projects/{project_id}/open")

    existing = find_node(project_id, NODE_NAME)
    if existing:
        print(f"{NODE_NAME} already exists: {existing['node_id'][:8]}")
        sys.exit(0)

    sw30 = find_node(project_id, "SW-VLAN30")
    if not sw30:
        print("SW-VLAN30 not found")
        sys.exit(1)

    set_ports(project_id, sw30["node_id"])
    admin = create_node(project_id)
    create_link(project_id, admin["node_id"], sw30["node_id"])
    print("Done. Refresh GNS3 GUI to see Admin-Linux in VLAN30.")