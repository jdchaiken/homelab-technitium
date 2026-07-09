# Documentation Map

A guided path through this repository's documentation, grouped by what
you're trying to do. For a flat categorized list of every doc, see
docs/INDEX.md.

---

## New to this repo?

Read in this order:

1. docs/GETTING-STARTED.md — fastest path to understanding the platform
2. docs/ONBOARDING.md — how to make and submit a DNS change
3. docs/ARCHITECTURE.md — how the pieces fit together
   (see also ARCHITECTURE-DIAGRAM.md / ARCHITECTURE-MERMAID.md for
   visual versions, and INFRA-OVERVIEW.md for a simplified box diagram)

## Setting up the infrastructure from scratch?

- INSTALL.md — full install/bootstrap walkthrough, including the
  "manual-edit" variables you must set before `make deploy`
- docs/SECRETS-FLOW.md — how credentials move from Proxmox to Technitium
- docs/LIFECYCLE.md — what `terraform apply` actually does, step by step

## Running day-to-day operations?

- docs/OPERATIONS.md — daily operator tasks
- docs/CHEATSHEET.md — copy-pasteable command reference
- docs/DNS-QUICKSTART.md — adding/editing DNS records
- docs/TSIG-ROTATION.md — rotating the RFC2136 TSIG key
- docs/OUTAGE-RUNBOOK.md — what to do when DNS is down

## Understanding CI/CD?

- docs/CI-PIPELINE.md — what the Gitea workflow checks and how to
  reproduce failures locally
- docs/CI-DIAGRAM.md / docs/WORKFLOW-DIAGRAM.md — visual pipeline flow
- docs/TSIG-DIAGRAM.md — TSIG key flow diagram

## Contributing code or docs?

- docs/DEV-QUICKSTART.md — developer machine setup
- CONTRIBUTING.md — contribution guidelines
- SECURITY.md — secret handling and security principles
- CHANGELOG.md — release history

## Looking for a specific file?

See docs/INDEX.md for the complete categorized list of every doc and
script in this repository.
