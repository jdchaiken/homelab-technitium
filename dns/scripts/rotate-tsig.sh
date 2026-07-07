#!/bin/bash
set -e

echo "=== TSIG Rotation Procedure ==="
echo "1. Create a new TSIG key in Technitium UI."
echo "2. Copy the new TSIG Name, Algorithm, and Secret."
echo "3. Create three new Bitwarden Secrets:"
echo "   - externaldns-tsig-name"
echo "   - externaldns-tsig-algorithm"
echo "   - externaldns-tsig-secret"
echo "4. Copy the new Secret IDs."
echo "5. Update configure-technitium.yaml with the new Secret IDs."
echo "6. Rebuild the Technitium VM using the zero-downtime workflow."
echo ""
echo "This script does not rotate keys automatically — it documents the safe workflow."
