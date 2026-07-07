#!/usr/bin/env bash
set -euo pipefail

# Scan Proxmox for next free VMID in the GitOps range 4000–4999
next=$(pvesh get /cluster/resources --type vm \
    | jq -r '.[].vmid' \
    | awk '$1>=4000 && $1<=4999' \
    | sort -n \
    | awk 'END {print $1+1}')

# Wrap around if needed
if [[ -z "$next" || "$next" -gt 4999 ]]; then
  next=4000
fi

# Terraform external data source requires JSON output
echo "{\"vmid\": \"$next\"}"
