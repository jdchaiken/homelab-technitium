#!/bin/bash
set -e

MAIN_BRANCH="HEAD~1"
ZONE_DIR="dns/zones"

echo "=== Strict Zone Diff Checker ==="

# HEAD~1 (the pushed commit's actual parent), not origin/main: this repo
# pushes directly to main (no PR workflow), so by the time CI runs
# `git fetch origin main`, origin/main has already been updated to the same
# commit as HEAD -- current serial == "main" serial every time, and this
# check could never pass. update-serials.sh bumps every zone's serial
# together on every invocation (confirmed repo convention), so comparing
# against the immediate parent commit is consistent with how a real change
# actually gets committed here.

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

    # Check syntax
    if ! named-checkzone "$ZONE_BASE" "$zone" >/dev/null 2>&1; then
        echo "❌ ERROR: Zone $ZONE_NAME failed syntax validation."
        EXIT_CODE=1
    else
        echo "✔ Zone syntax OK"
    fi

    # Serial increment is only required when this zone actually changed --
    # a push that only touches one zone file shouldn't fail the other two,
    # untouched ones just for having an identical (and therefore "not
    # incremented") serial relative to the parent commit.
    if git diff --quiet "${MAIN_BRANCH}" -- "${ZONE_DIR}/${ZONE_NAME}"; then
        echo "✔ No record changes detected"
    else
        echo "⚠️ Record changes detected:"
        git diff --color=always "${MAIN_BRANCH}" -- "${ZONE_DIR}/${ZONE_NAME}" || true

        if [[ "$CURRENT_SERIAL" -le "$MAIN_SERIAL" ]]; then
            echo "❌ ERROR: Zone $ZONE_NAME has record changes WITHOUT serial increment."
            echo "   Serial must strictly increase."
            EXIT_CODE=1
        else
            echo "✔ SOA serial increment OK"
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
