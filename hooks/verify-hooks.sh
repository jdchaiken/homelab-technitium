#!/usr/bin/env bash

echo "Verifying Git hook installation..."

HOOK_DIR=".git/hooks"

# Map of expected hooks and their source files
declare -A HOOKS
HOOKS["pre-commit"]="hooks/pre-commit"
HOOKS["pre-push"]="hooks/pre-push"
HOOKS["commit-msg"]="hooks/commit-msg"

missing=0

for hook in "${!HOOKS[@]}"; do
    src="${HOOKS[$hook]}"
    dst="$HOOK_DIR/$hook"

    if [ ! -f "$dst" ]; then
        echo "ERROR: Missing hook: $dst"
        missing=1
        continue
    fi

    # Compare contents
    if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
        echo "ERROR: Hook mismatch: $hook"
        echo "Run: make install-hooks"
        missing=1
    else
        echo "OK: $hook is installed and matches repository version."
    fi
done

if [ "$missing" -eq 1 ]; then
    echo ""
    echo "One or more hooks are missing or outdated."
    echo "Run: make install-hooks"
    exit 1
fi

echo ""
echo "All Git hooks are correctly installed."
exit 0
