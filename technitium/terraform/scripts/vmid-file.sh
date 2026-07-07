#!/bin/bash
set -e

FILE="vmid.txt"
START=4000
END=4999

if [ ! -f "$FILE" ]; then
    echo $START > "$FILE"
fi

CURRENT=$(cat "$FILE")
NEXT=$((CURRENT + 1))

if [ "$NEXT" -gt "$END" ]; then
    NEXT=$START
fi

echo $NEXT > "$FILE"
echo $NEXT
