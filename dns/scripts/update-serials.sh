#!/bin/bash
set -e

DATE=$(date +%Y%m%d)

for zone in zones/*.zone; do
    echo "Updating serial for $zone"
    SERIAL=$(grep -Eo '[0-9]{10}' "$zone" | head -n1)
    PREFIX=${SERIAL:0:8}
    SUFFIX=${SERIAL:8:2}

    if [ "$PREFIX" == "$DATE" ]; then
        NEW_SUFFIX=$(printf "%02d" $((10#$SUFFIX + 1)))
    else
        NEW_SUFFIX="01"
    fi

    NEW_SERIAL="${DATE}${NEW_SUFFIX}"

    sed -i "s/$SERIAL/$NEW_SERIAL/" "$zone"
    echo "New serial: $NEW_SERIAL"
done

# Usage:
# make validate-zones
# scripts/update-serials.sh
# git commit -am "Update SOA serials"
