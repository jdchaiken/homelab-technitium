#!/usr/bin/env bash
set -euo pipefail

# Technitium VMIDs are reserved to this range. Cluster-wide VMIDs outside it
# (other services, templates, etc.) must not influence allocation here.
RANGE_MIN=4000
RANGE_MAX=4999

VMIDS=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq -r '.[].vmid' 2>/dev/null || true)

IN_RANGE=$(echo "$VMIDS" | awk -v min="$RANGE_MIN" -v max="$RANGE_MAX" '$1 >= min && $1 <= max')

if [ -z "$IN_RANGE" ]; then
  NEXT_VMID=$RANGE_MIN
else
  MAX_VMID=$(echo "$IN_RANGE" | sort -n | tail -1)
  NEXT_VMID=$((MAX_VMID + 1))

  if [ "$NEXT_VMID" -gt "$RANGE_MAX" ]; then
    echo "No available VMIDs left in range $RANGE_MIN-$RANGE_MAX" >&2
    exit 1
  fi
fi

printf '{"vmid":"%s"}\n' "$NEXT_VMID"
