# GitOps DNS Architecture

This document describes the full architecture of the GitOps-managed DNS system.

---

# 1. Overview

The system provides authoritative DNS for internal domains using:

- Technitium DNS Server
- Proxmox virtualization
- Terraform VM lifecycle automation
- Cloud-init provisioning
- Ansible configuration
- Bitwarden Secrets Manager
- Gitea CI/CD validation
- Strict DNS policy enforcement

Everything is declarative. Everything is reproducible.

---

# 2. High-Level Flow

    Git → CI/CD → Terraform → Proxmox → Cloud-init → Ansible → Technitium

---

# 3. Components

## DNS Zones (dns/zones/)
Authoritative zone files for internal domains.

## Validation (dns/scripts/)
- Syntax validation
- Strict diff checker
- Serial auto-increment
- TSIG rotation helper

## CI/CD (dns/ci/)
Gitea workflows enforcing DNS correctness.

## Technitium (technitium/)
- Ansible install + configure
- Cloud-init bootstrap
- Terraform VM lifecycle
- VMID allocator

## Secrets (secrets/)
Bitwarden env templates.

---

# 4. VM Lifecycle

Terraform:

1. Allocates VMID (4000–4999)
2. Creates temporary VM (172.16.100.7)
3. Applies cloud-init
4. Runs Ansible
5. Validates DNS
6. Stops old VM
7. Swaps IPs
8. Destroys old VM

Zero downtime.

---

# 5. TSIG Key Management

TSIG keys stored in Bitwarden.

Ansible retrieves:

- TSIG Name
- TSIG Algorithm
- TSIG Secret

Using Secret IDs.

---

# 6. CI/CD Enforcement

CI/CD ensures:

- SOA serial increments
- No accidental changes
- No drift from main
- No malformed SOA
- No accidental deletions/additions

---

# 7. Security

- Secrets never stored in Git
- Bitwarden credentials stored in Proxmox
- Cloud-init copies secrets securely
- Ansible fetches secrets at runtime

---

# 8. Summary

This architecture provides:

- Declarative DNS
- Declarative VM lifecycle
- Declarative secrets
- Strict CI/CD validation
- Zero-downtime rebuilds

Everything is automated.
