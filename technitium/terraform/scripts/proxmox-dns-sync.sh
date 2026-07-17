#!/usr/bin/env bash
# Publishes an A record in Technitium for every running VM/CT in the
# Proxmox cluster, keyed off Proxmox's own name/IP -- so infrastructure
# hosts don't need to be hand-maintained in dns/zones/*.zone.
#
# Meant to run ON a Proxmox node (uses pvesh directly), on a periodic
# systemd timer -- see proxmox-dns-sync.timer alongside this script.
#
# This SCRIPT lives in /etc/pve/technitium/ (pmxcfs, the Proxmox cluster
# filesystem) -- automatically replicated to every node, not copied
# per-node. The systemd .service/.timer UNIT FILES still have to be
# deployed to each node's local /etc/systemd/system/ (systemd can't
# discover units from /etc/pve/ directly), and are installed + enabled on
# ALL FOUR nodes, not just one -- see INSTALL.md. Without that, this
# sync would have a single point of failure: whichever one node it ran
# from. With all four nodes' timers active and the lock below, the sync
# keeps running even if the node that normally wins the lock goes down --
# the next timer fire on any surviving node picks it up within one
# 15-minute cycle, no manual failover needed.
#
# IP discovery, per VM/CT type -- all through `pvesh` (the cluster-wide
# REST API), never bare `qm`/`pct`: those are node-local and only work
# for VMs/CTs actually running on the node you invoke them from, but
# this script runs from a single node at a time while VMs are spread
# across all four (confirmed live: `pvesh get /nodes/<node>/...` proxies
# to whichever node actually holds that VM/CT, regardless of which node
# you run it from):
#   - qemu (VM): QEMU guest agent
#     (`/nodes/<node>/qemu/<vmid>/agent/network-get-interfaces`) if the
#     VM is running and the agent responds -- picks the first
#     non-loopback, non-link-local IPv4. Falls back to the static IP in
#     `ipconfig0` (`/nodes/<node>/qemu/<vmid>/config`) if the agent is
#     unavailable/not installed/VM stopped.
#   - lxc (container): static IP from `net0`
#     (`/nodes/<node>/lxc/<vmid>/config`) -- LXC guest agent
#     introspection isn't as standardized as QEMU's, so this only
#     handles static configs. DHCP-assigned containers are skipped (no
#     way to determine the IP without an agent).
#
# Proxmox's own cluster NODES (pve01-04 themselves) are never covered by
# any of this -- `/cluster/resources --type vm` only returns VMs/CTs, not
# nodes, so they always need a manual zone-file entry regardless of what
# else this script picks up.
#
# Reconciliation, not blind overwrite: a state file (STATE_FILE below,
# in cluster storage alongside the script) tracks exactly which
# hostnames THIS script previously published. Only those get updated or
# removed on each run -- a VM/CT this script has never seen is added
# fresh; a hostname that disappears from Proxmox (destroyed VM) gets its
# DNS record removed; anything NOT in the state file (manually created
# records, or records from ExternalDNS/Kea) is never touched. This is
# deliberately similar to ExternalDNS's TXT-record ownership tracking,
# just via a local file instead of an in-zone marker, since this script
# authenticates as full admin (not a scoped dynamic-update client) and a
# mistaken bulk-delete would be a lot more damaging here than it would
# be for ExternalDNS.
set -euo pipefail

CLUSTER_DIR="/etc/pve/technitium"
STATE_FILE="${CLUSTER_DIR}/proxmox-dns-sync-state.json"
LOCK_FILE="${CLUSTER_DIR}/proxmox-dns-sync.lock"
BW_ENV="${CLUSTER_DIR}/bw.env"

# TECHNITIUM_API/ZONE are read from bw.env below (PROXMOX_DNS_SYNC_*
# keys) so custom config lives in one place alongside the secrets this
# script already reads from there -- these hardcoded values are only the
# fallback if bw.env doesn't set them, not the source of truth.
DEFAULT_TECHNITIUM_API="https://172.16.100.6:8443/api"
DEFAULT_ZONE="example.com"

# Longer than a normal run (~60-70s for ~20 VMs) but comfortably shorter
# than the 15-minute timer interval, so a run that crashed mid-way
# without clearing its lock doesn't block a full cycle on every other
# node -- the next scheduled fire anywhere sees the lock as stale and
# takes over anyway.
LOCK_STALE_SECONDS=600

# Proxmox objects that are Technitium's own build/production VMs -- these
# already have real, authoritative records (ns1/ns2 A + NS) from the zone
# file itself; publishing them again here would just be redundant, and
# the transient blue-green build names would leak a churning, meaningless
# record into the zone on every rebuild.
EXCLUDE_NAMES="^(ns1|ns2|technitium-temp|technitium-ns2-temp)$"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# --- 0. Cluster-wide lock: only one node's timer fire actually runs the
# sync at a time. All four nodes have this timer enabled (for resilience
# if one node is down), so without this every node would race to write
# the same DNS records simultaneously on every interval. ---
NOW=$(date +%s)
if [ -f "$LOCK_FILE" ]; then
    LOCK_HOST=$(cut -d' ' -f1 "$LOCK_FILE" 2>/dev/null || echo "")
    LOCK_TIME=$(cut -d' ' -f2 "$LOCK_FILE" 2>/dev/null || echo "0")
    LOCK_AGE=$((NOW - LOCK_TIME))
    if [ "$LOCK_HOST" != "$(hostname)" ] && [ "$LOCK_AGE" -lt "$LOCK_STALE_SECONDS" ]; then
        log "Lock held by ${LOCK_HOST} (${LOCK_AGE}s ago) -- skipping this run"
        exit 0
    fi
fi
echo "$(hostname) ${NOW}" > "$LOCK_FILE"

# --- 1. Load config + authenticate to Technitium (fresh session token
# every run -- the admin password is stable, unlike the TSIG key/API
# key, which regenerate on every ns1 rebuild) ---
BW_ENV_RAW=$(cat "$BW_ENV")
ADMIN_PASS=$(echo "$BW_ENV_RAW" | grep -oP 'TECHNITIUM_ADMIN_PASSWORD="?\K[^"\n]+')
TECHNITIUM_API=$(echo "$BW_ENV_RAW" | grep -oP 'PROXMOX_DNS_SYNC_TECHNITIUM_API="?\K[^"\n]+' || echo "$DEFAULT_TECHNITIUM_API")
ZONE=$(echo "$BW_ENV_RAW" | grep -oP 'PROXMOX_DNS_SYNC_ZONE="?\K[^"\n]+' || echo "$DEFAULT_ZONE")

TOKEN=$(curl -sk -X POST "${TECHNITIUM_API}/user/login" \
    --data-urlencode "user=admin" --data-urlencode "pass=${ADMIN_PASS}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

if [ -z "$TOKEN" ]; then
    log "ERROR: failed to authenticate to Technitium"
    exit 1
fi

# --- 2. Enumerate current VMs/CTs and resolve each one's IP ---
# All Proxmox introspection below goes through `pvesh` (the cluster-wide
# REST API), never bare `qm`/`pct` -- those are node-local and only work
# for VMs/CTs actually running on the node you invoke them from, but this
# script runs from a single node while VMs are spread across all 4.
# `pvesh get /nodes/<node>/...` proxies to whichever node actually holds
# that VM/CT, confirmed live against a VM on a different node than where
# this runs.
CURRENT_JSON=$(python3 <<PYEOF
import json, subprocess, re, sys

exclude_re = re.compile(r"$EXCLUDE_NAMES")

def sanitize(name):
    name = name.lower().strip()
    name = re.sub(r"[^a-z0-9-]+", "-", name)
    name = name.strip("-")
    return name

def pvesh_get(path):
    out = subprocess.run(
        ["pvesh", "get", path, "--output-format", "json"],
        capture_output=True, text=True, timeout=15,
    )
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None

def qemu_agent_ip(node, vmid):
    data = pvesh_get(f"/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces")
    if not data:
        return None
    for iface in data.get("result", []):
        if iface.get("name") == "lo":
            continue
        for addr in iface.get("ip-addresses", []):
            if addr.get("ip-address-type") != "ipv4":
                continue
            ip = addr["ip-address"]
            if ip.startswith("169.254.") or ip == "127.0.0.1":
                continue
            return ip
    return None

def qemu_static_ip(node, vmid):
    data = pvesh_get(f"/nodes/{node}/qemu/{vmid}/config")
    if not data:
        return None
    m = re.search(r"ip=([0-9.]+)/", data.get("ipconfig0", "") or "")
    return m.group(1) if m else None

def lxc_static_ip(node, vmid):
    data = pvesh_get(f"/nodes/{node}/lxc/{vmid}/config")
    if not data:
        return None
    m = re.search(r"ip=([0-9.]+)/", data.get("net0", "") or "")
    return m.group(1) if m else None

resources = json.loads(subprocess.run(
    ["pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"],
    capture_output=True, text=True, timeout=30,
).stdout)

result = {}
for r in resources:
    if r.get("template"):
        continue
    name = sanitize(r.get("name", ""))
    if not name or exclude_re.match(name):
        continue

    node, vmid = r["node"], r["vmid"]
    if r["type"] == "qemu":
        ip = None
        if r.get("status") == "running":
            ip = qemu_agent_ip(node, vmid)
        if not ip:
            ip = qemu_static_ip(node, vmid)
    elif r["type"] == "lxc":
        ip = lxc_static_ip(node, vmid)
    else:
        continue

    if ip:
        result[name] = ip

print(json.dumps(result))
PYEOF
)

log "Discovered $(echo "$CURRENT_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))') VM/CT records with a resolvable IP"

# --- 3. Load previous state (records this script owns) ---
if [ -f "$STATE_FILE" ]; then
    PREVIOUS_JSON=$(cat "$STATE_FILE")
else
    PREVIOUS_JSON="{}"
fi

# --- 4. Diff and apply: add/update changed, remove disappeared ---
python3 <<PYEOF
import json, subprocess

current = json.loads('''$CURRENT_JSON''')
previous = json.loads('''$PREVIOUS_JSON''')
zone = "$ZONE"
token = "$TOKEN"
api = "$TECHNITIUM_API"

def add_record(name, ip):
    subprocess.run(
        ["curl", "-sk", "-f", "-X", "POST", f"{api}/zones/records/add",
         "-H", f"Authorization: Bearer {token}",
         "--data-urlencode", f"zone={zone}",
         "--data-urlencode", f"domain={name}.{zone}",
         "--data-urlencode", "type=A",
         "--data-urlencode", f"ipAddress={ip}",
         "--data-urlencode", "ttl=300",
         "--data-urlencode", "overwrite=true"],
        check=True, capture_output=True,
    )

def delete_record(name, ip):
    subprocess.run(
        ["curl", "-sk", "-f", "-X", "POST", f"{api}/zones/records/delete",
         "-H", f"Authorization: Bearer {token}",
         "--data-urlencode", f"zone={zone}",
         "--data-urlencode", f"domain={name}.{zone}",
         "--data-urlencode", "type=A",
         "--data-urlencode", f"ipAddress={ip}"],
        check=True, capture_output=True,
    )

added = updated = removed = unchanged = 0

for name, ip in current.items():
    if name not in previous:
        add_record(name, ip)
        added += 1
        print(f"ADD    {name}.{zone} -> {ip}")
    elif previous[name] != ip:
        add_record(name, ip)
        updated += 1
        print(f"UPDATE {name}.{zone} -> {ip} (was {previous[name]})")
    else:
        unchanged += 1

for name, ip in previous.items():
    if name not in current:
        delete_record(name, ip)
        removed += 1
        print(f"REMOVE {name}.{zone} (was {ip})")

print(f"SUMMARY added={added} updated={updated} removed={removed} unchanged={unchanged}")
PYEOF

# --- 5. Persist new state ---
echo "$CURRENT_JSON" > "$STATE_FILE"
log "Sync complete, state written to $STATE_FILE"
