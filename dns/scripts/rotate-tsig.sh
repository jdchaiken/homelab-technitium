#!/bin/bash
set -e

echo "=== TSIG Rotation Procedure ==="
echo "1. Run 'make deploy'."
echo "2. This builds a fresh VM; configure-technitium.yaml automatically"
echo "   generates a new 'externaldns-key' TSIG key and overwrites these"
echo "   Bitwarden secrets with the new values:"
echo "   - externaldns-tsig-name"
echo "   - externaldns-tsig-algorithm"
echo "   - externaldns-tsig-secret"
echo "3. Point ExternalDNS at the refreshed secret values."
echo "4. Verify with: dig @PROD_VM_IP SOA"
echo ""
echo "This script does not rotate keys automatically — it documents the workflow."
echo "See docs/TSIG-ROTATION.md for details."
