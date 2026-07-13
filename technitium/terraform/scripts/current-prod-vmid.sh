#!/usr/bin/env bash
set -euo pipefail

# Finds whichever VM currently holds prod_ip, so Terraform never needs a
# manually-maintained "old_vm_id" that has to be updated by hand before
# every rebuild. Scoped to the same reserved range as next-vmid.sh so a
# coincidental IP match on some unrelated VM outside that range can never
# be mistaken for the current production Technitium VM.
RANGE_MIN=4000
RANGE_MAX=4999

PROD_IP=$(jq -r '.prod_ip')

VMIDS=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | jq -r '.[].vmid' 2>/dev/null || true)
IN_RANGE=$(echo "$VMIDS" | awk -v min="$RANGE_MIN" -v max="$RANGE_MAX" '$1 >= min && $1 <= max')

FOUND=""
for id in $IN_RANGE; do
  if qm config "$id" 2>/dev/null | grep -q "ip=${PROD_IP}/"; then
    FOUND="$id"
    break
  fi
done

printf '{"vmid":"%s"}\n' "$FOUND"
