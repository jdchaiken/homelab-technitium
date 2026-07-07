#!/bin/bash
set -e

MAIN_BRANCH="origin/main"
ZONE_DIR="zones"

echo "=== Strict Zone Diff Checker ==="

git fetch origin main

EXIT_CODE=0

for zone in "${ZONE_DIR}"/*.zone; do
    ZONE_NAME=$(basename "$zone")
    ZONE_BASE="${ZONE_NAME%.zone}"

    echo ""
    echo "Checking zone: $ZONE_NAME"

    # Extract current serial
    CURRENT_SERIAL=$(grep -Eo '[0-9]{10}' "$zone" | head -n1)
    if [[ -z "$CURRENT_SERIAL" ]]; then
        echo "❌ ERROR: Zone $ZONE_NAME missing SOA serial."
        EXIT_CODE=1
        continue
    fi

    # Extract main branch serial
    MAIN_SERIAL=$(git show "${MAIN_BRANCH}:${ZONE_DIR}/${ZONE_NAME}" | grep -Eo '[0-9]{10}' | head -n1 || true)
    if [[ -z "$MAIN_SERIAL" ]]; then
        echo "❌ ERROR: Zone $ZONE_NAME missing SOA serial in main branch."
        EXIT_CODE=1
        continue
    fi

    echo "Main serial:    $MAIN_SERIAL"
    echo "Current serial: $CURRENT_SERIAL"

    # Ensure serial increments
    if [[ "$CURRENT_SERIAL" -le "$MAIN_SERIAL" ]]; then
        echo "❌ ERROR: SOA serial for $ZONE_NAME did NOT increment."
        echo "   Serial must strictly increase."
        EXIT_CODE=1
    else
        echo "✔ SOA serial increment OK"
    fi

    # Check syntax
    if ! named-checkzone "$ZONE_BASE" "$zone" >/dev/null 2>&1; then
        echo "❌ ERROR: Zone $ZONE_NAME failed syntax validation."
        EXIT_CODE=1
    else
        echo "✔ Zone syntax OK"
    fi

    # Check for any diff
    if git diff --quiet "${MAIN_BRANCH}" -- "${ZONE_DIR}/${ZONE_NAME}"; then
        echo "✔ No record changes detected"
    else
        echo "⚠️ Record changes detected:"
        git diff --color=always "${MAIN_BRANCH}" -- "${ZONE_DIR}/${ZONE_NAME}" || true

        # If records changed but serial didn't increment, fail
        if [[ "$CURRENT_SERIAL" -le "$MAIN_SERIAL" ]]; then
            echo "❌ ERROR: Zone $ZONE_NAME has record changes WITHOUT serial increment."
            EXIT_CODE=1
        fi
    fi
done

echo ""
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "❌ Strict zone diff check failed."
else
    echo "✔ All zones validated successfully (strict mode)."
fi

exit $EXIT_CODE
