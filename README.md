# GitOps DNS Platform

A fully declarative, GitOps-driven DNS platform built on Technitium DNS,
Terraform, Proxmox, Cloud-init, Ansible, and Gitea CI/CD.

This repository manages:

- Authoritative DNS zones
- Technitium DNS server configuration
- VM lifecycle (Terraform + Proxmox)
- Secrets (Bitwarden → Proxmox → Cloud-init → Ansible)
- CI/CD validation and enforcement

Everything is reproducible, version-controlled, and zero-downtime.

---

## Documentation

Start here:

- [Getting Started](docs/GETTING-STARTED.md)
- [Onboarding Guide](docs/ONBOARDING.md)
- [Developer Quickstart](docs/DEV-QUICKSTART.md)
- [AI.md](AI.md) — working rules and hard-won gotchas, for an AI
  assistant operating in this repo
- [Operator Cheat Sheet](docs/CHEATSHEET.md)

Architecture:

- [Architecture Overview](docs/ARCHITECTURE.md)
- [Architecture Diagram](docs/ARCHITECTURE-DIAGRAM.md)
- [Architecture (Mermaid)](docs/ARCHITECTURE-MERMAID.md)

Workflows:

- [DNS Lifecycle](docs/LIFECYCLE.md)
- [TSIG Rotation](docs/TSIG-ROTATION.md)
- [Secrets Flow](docs/SECRETS-FLOW.md)
- [CI Pipeline](docs/CI-PIPELINE.md)

Operations:

- [Operations Guide](docs/OPERATIONS.md)
- [Outage Runbook](docs/OUTAGE-RUNBOOK.md)

---

## Key Features

- Declarative DNS zones
- Strict CI validation (syntax, diff, serials)
- Git hook enforcement (secrets, commit-msg, pre-push)
- Zero-downtime VM rebuilds
- Automated TSIG rotation
- RFC2136 dynamic updates
- Full GitOps workflow

---

## Quick Commands

Validate zones:

    make validate-zones

Deploy:

    make deploy

Install Git hooks:

    make install-hooks
    make verify-hooks

---

## Zero-Downtime Rebuild

All changes flow through:

Git → CI → Terraform → Proxmox → Cloud-init → Ansible → Technitium

The system automatically cuts over to a new VM without downtime.

---

## License

Internal use only.
