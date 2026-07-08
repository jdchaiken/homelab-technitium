#!/usr/bin/env bash
set -euo pipefail

VMIDS=$(pvesh get /cluster/resources --type vm 2>/dev/null | jq -r '.[].vmid' 2>/dev/null || true)

if [ -z "$VMIDS" ]; then
  NEXT_VMID=4000
else
  MAX_VMID=$(echo "$VMIDS" | sort -n | tail -1)
  NEXT_VMID=$((MAX_VMID + 1))
fi

printf '{"vmid":"%s"}\n' "$NEXT_VMID"
