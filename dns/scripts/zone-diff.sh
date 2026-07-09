#!/bin/bash
set -e

MAIN_BRANCH="origin/main"
ZONE_DIR="dns/zones"

echo "=== Zone Diff Checker ==="

# Ensure main branch is available
git fetch origin main

EXIT_CODE=0

for zone in "${ZONE_DIR}"/*.zone; do
    ZONE_NAME=$(basename "$zone")

    echo ""
    echo "Checking zone: $ZONE_NAME"

    # Compare against main branch version
    git diff --color=always ${MAIN_BRANCH} -- "${ZONE_DIR}/${ZONE_NAME}" || true

    # Check if file changed
    if ! git diff --quiet ${MAIN_BRANCH} -- "${ZONE_DIR}/${ZONE_NAME}"; then
        echo "⚠️  Zone ${ZONE_NAME} has changes."
        EXIT_CODE=1
    fi

    # Validate syntax
    if ! named-checkzone "${ZONE_NAME%.zone}" "${ZONE_DIR}/${ZONE_NAME}" >/dev/null 2>&1; then
        echo "❌ Zone ${ZONE_NAME} failed syntax validation."
        EXIT_CODE=1
    else
        echo "✔ Zone syntax OK"
    fi

    # Check SOA serial consistency
    SERIAL=$(grep -Eo '[0-9]{10}' "${ZONE_DIR}/${ZONE_NAME}" | head -n1)
    if [[ -z "$SERIAL" ]]; then
        echo "❌ Zone ${ZONE_NAME} missing SOA serial."
        EXIT_CODE=1
    else
        echo "✔ SOA serial: $SERIAL"
    fi
done

echo ""
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "❌ Zone diff check failed."
else
    echo "✔ All zones validated successfully."
fi

exit $EXIT_CODE
