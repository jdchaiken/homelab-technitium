#!/bin/bash
# Pushes the current dns/zones/*.zone content to the live, already-running
# ns1 via the Technitium API (zones/import), skipping the full blue-green
# VM rebuild -- for quick record-only changes. ns2 picks up the change on
# its own via the existing zone-transfer/NOTIFY mechanism, same as any
# other update to ns1. Serial bumping and validation are handled by the
# `update-zones` Make target this script is meant to run after (see
# `make push-zones` in the Makefile).
set -e

cd "$(dirname "$0")/.."

TECHNITIUM_IP="172.16.100.6"

# Discovered from zone_dir rather than hardcoded, so adding/removing a zone
# is just adding/removing a .zone file -- no script edit needed.
ZONES=()
for f in zones/*.zone; do
    ZONES+=("$(basename "$f" .zone)")
done

echo "Pushing zone files to live Technitium (${TECHNITIUM_IP})..."

for zone in "${ZONES[@]}"; do
    echo "  -> ${zone}"
    ssh -o StrictHostKeyChecking=accept-new "root@${TECHNITIUM_IP}" '
        set -e
        PASS=$(grep -oP '"'"'TECHNITIUM_ADMIN_PASSWORD="\K[^"]+'"'"' /root/bw.env)
        TOKEN=$(curl -sk -X POST https://127.0.0.1:8443/api/user/login -d "user=admin&pass=${PASS}" | grep -oP '"'"'"token":"\K[^"]+'"'"')
        curl -sk -f -X POST "https://127.0.0.1:8443/api/zones/import?zone='"${zone}"'&overwrite=true&overwriteSoaSerial=true" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: text/plain" \
            --data-binary @-

        # The zone file must carry NS records for named-checkzone to accept
        # it (make validate-zones), but a Forwarder zone with local NS
        # records for itself breaks Conditional Forwarder fallback --
        # Technitium attempts real self-referential recursive resolution
        # instead of using the FWD record for any name not explicitly
        # listed in the zone file. Delete them from the live zone right
        # after every import. Confirmed live 2026-07-17, see AI.md.
        curl -sk -f -X POST "https://127.0.0.1:8443/api/zones/records/delete?zone='"${zone}"'&domain='"${zone}"'&type=NS&nameServer=ns1.'"${zone}"'" \
            -H "Authorization: Bearer ${TOKEN}" > /dev/null
        curl -sk -f -X POST "https://127.0.0.1:8443/api/zones/records/delete?zone='"${zone}"'&domain='"${zone}"'&type=NS&nameServer=ns2.'"${zone}"'" \
            -H "Authorization: Bearer ${TOKEN}" > /dev/null
    ' < "zones/${zone}.zone"
    echo
done

echo "Committing and pushing zone file changes to git..."
cd ..
git add dns/zones/*.zone

if git diff --cached --quiet -- dns/zones/; then
    echo "No zone file changes to commit."
else
    git commit -m "chore: push zone record changes"
    git push origin main
fi

echo "push-zones complete."
