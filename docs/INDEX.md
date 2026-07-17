# Documentation Index

This index provides a quick reference to all documentation in the GitOps DNS repository.

---------------------------------------------------------------------
Start Here
---------------------------------------------------------------------
- GETTING-STARTED.md
- DOC-MAP.md
- FEATURES.md -- what infrastructure technology this project touches
  and why, at a glance
- TODO.md -- proposed, scoped future work (not yet started)
- ../AI.md -- working rules and hard-won gotchas, for an AI assistant
  operating in this repo

---------------------------------------------------------------------
Architecture
---------------------------------------------------------------------
- ARCHITECTURE.md
- ARCHITECTURE-DIAGRAM.md
- ARCHITECTURE-MERMAID.md
- INFRA-OVERVIEW.md
- LIFECYCLE.md
- SECRETS-FLOW.md
- VMID.md

---------------------------------------------------------------------
CI/CD
---------------------------------------------------------------------
- CI-PIPELINE.md
- CI-DIAGRAM.md
- WORKFLOW-DIAGRAM.md
- TSIG-DIAGRAM.md

---------------------------------------------------------------------
Operations
---------------------------------------------------------------------
- ONBOARDING.md
- INSTALL.md
- OPERATIONS.md
- OUTAGE-RUNBOOK.md
- CHEATSHEET.md
- DNS-QUICKSTART.md
- TSIG-ROTATION.md

---------------------------------------------------------------------
Development
---------------------------------------------------------------------
- DEV-QUICKSTART.md
- CONTRIBUTING.md
- CHANGELOG.md
- SECURITY.md

---------------------------------------------------------------------
Scripts
---------------------------------------------------------------------
DNS Scripts:
- dns/scripts/zone-diff.sh
- dns/scripts/zone-diff-strict.sh
- dns/scripts/update-serials.sh
- dns/scripts/rotate-tsig.sh

Developer Scripts:
- dns/scripts/bootstrap-dev.sh
- dns/scripts/verify-dev.sh

Terraform Scripts:
- technitium/terraform/scripts/next-vmid.sh
- technitium/terraform/scripts/current-prod-vmid.sh
- technitium/terraform/scripts/vmid-file.sh
- technitium/terraform/scripts/proxmox-dns-sync.sh (+ .service/.timer) --
  periodic Proxmox VM/CT -> Technitium DNS sync, see OPERATIONS.md § 9
