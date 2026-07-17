#!/usr/bin/env bash
# Publishes an A record in Technitium for every running VM/CT in the
# Proxmox cluster, keyed off Proxmox's own name/IP -- so infrastructure
# hosts don't need to be hand-maintained in dns/zones/*.zone.
#
# Meant to run ON a Proxmox node (uses pvesh/qm/pct directly), on a
# periodic systemd timer -- see proxmox-dns-sync.timer alongside this
# script. Deployed the same way as next-vmid.sh/current-prod-vmid.sh:
# manually copied to /opt/infra/technitium/ on the Proxmox host, no
# automated sync from git for these.
#
# IP discovery, per VM/CT type:
#   - qemu (VM): QEMU guest agent (`qm guest cmd <vmid>
#     network-get-interfaces`) if the VM is running and the agent
#     responds -- picks the first non-loopback, non-link-local IPv4.
#     Falls back to the static IP in `ipconfig0` (qm config) if the agent
#     is unavailable/not installed/VM stopped.
#   - lxc (container): static IP from `net0` in `pct config` -- LXC guest
#     agent introspection isn't as standardized as QEMU's, so this only
#     handles static configs. DHCP-assigned containers are skipped (no
#     way to determine the IP without an agent).
#
# Reconciliation, not blind overwrite: a local state file
# (STATE_FILE below) tracks exactly which hostnames THIS script
# previously published. Only those get updated or removed on each run --
# a VM/CT this script has never seen is added fresh; a hostname that
# disappears from Proxmox (destroyed VM) gets its DNS record removed;
# anything NOT in the state file (manually created records, or records
# from ExternalDNS/Kea) is never touched. This is deliberately similar to
# ExternalDNS's TXT-record ownership tracking, just via a local file
# instead of an in-zone marker, since this script authenticates as full
# admin (not a scoped dynamic-update client) and a mistaken bulk-delete
# would be a lot more damaging here than it would be for ExternalDNS.
#
# Known overlap: pve01-04, docker01-03, and nas01 are both real Proxmox
# VMs/nodes AND already hand-maintained in dns/zones/example.com.zone
# (re-imported on every ns1 rebuild). Until those manual entries are
# removed from the zone file, both sources are managing the same names --
# this script's writes will win between rebuilds, the zone file's import
# will win at rebuild time. Confirm this sync is reliable before removing
# the manual entries.
set -euo pipefail

TECHNITIUM_API="https://172.16.100.6:8443/api"
ZONE="example.com"
STATE_FILE="/opt/infra/technitium/proxmox-dns-sync-state.json"
BW_ENV="/etc/pve/technitium/bw.env"

# Proxmox objects that are Technitium's own build/production VMs -- these
# already have real, authoritative records (ns1/ns2 A + NS) from the zone
# file itself; publishing them again here would just be redundant, and
# the transient blue-green build names would leak a churning, meaningless
# record into the zone on every rebuild.
EXCLUDE_NAMES="^(ns1|ns2|technitium-temp|technitium-ns2-temp)$"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# --- 1. Authenticate to Technitium (fresh session token every run --
# the admin password is stable, unlike the TSIG key/API key, which
# regenerate on every ns1 rebuild) ---
ADMIN_PASS=$(grep -oP 'TECHNITIUM_ADMIN_PASSWORD="?\K[^"\n]+' "$BW_ENV")
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
