#!/bin/bash
set -e

echo "=== Verifying Developer Machine Requirements ==="

check() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "[OK] $1 found"
    else
        echo "[ERROR] $1 not found"
        MISSING=1
    fi
}

check terraform
check ansible
check ansible-playbook
check git
check ssh
check python3
check pip
check dig
check make

if [ "$MISSING" = "1" ]; then
    echo ""
    echo "One or more required tools are missing."
    echo "Install the missing tools before continuing."
    exit 1
fi

echo ""
echo "All developer tools are installed."
