# Getting Started

This page gives you the fastest path to understanding and using the GitOps DNS
platform.

---

## 1. What This Platform Does

- Manages DNS zones declaratively
- Rebuilds Technitium DNS with zero downtime
- Validates all DNS changes in CI
- Prevents secrets from being committed
- Automates TSIG rotation
- Stores secrets in Bitwarden → Proxmox → Cloud-init → Ansible

---

## 2. Start Here

1. Read the Onboarding Guide  
   docs/ONBOARDING.md

2. Install Git hooks  
   make install-hooks  
   make verify-hooks

3. Make a DNS change  
   docs/DEV-QUICKSTART.md

4. Deploy  
   make deploy

---

## 3. Architecture

See the full architecture diagram:

- docs/ARCHITECTURE-DIAGRAM.md
- docs/ARCHITECTURE-MERMAID.md

---

## 4. Daily Operator Tasks

See the Operator Cheat Sheet:

- docs/CHEATSHEET.md

---

## 5. CI/CD Pipeline

All DNS changes are validated automatically:

- Syntax
- Serial numbers
- Strict diffs
- Secrets scanning
- Terraform validation

See:

- docs/CI-PIPELINE.md

---

## 6. Troubleshooting

Outage or issues?

- docs/OUTAGE-RUNBOOK.md
