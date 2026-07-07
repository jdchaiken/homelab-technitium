#!/usr/bin/env bash
set -e

echo "Verifying developer environment..."

required_tools=(
  terraform
  ansible
  ansible-playbook
  git
  ssh
  python3
  pip
  dig
  jq
  yq
  make
  detect-secrets
  git-secrets
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Missing required tool: $tool"
        exit 1
    fi
done

echo "All required tools are installed."
