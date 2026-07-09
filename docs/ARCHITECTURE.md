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

## CI/CD (.gitea/workflows/zone-check.yaml)
Gitea workflow enforcing DNS correctness.

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

1. Allocates a VMID (via next-vmid.sh)
2. Creates the temporary VM from the cloud-init template
3. Waits for cloud-init to finish — cloud-init clones this repo onto the
   VM and runs the install + configure Ansible playbooks locally
   (Ansible is never invoked remotely from outside the VM)
4. Polls DNS on the temporary IP until Technitium answers
5. Stops the old VM, moves the new VM to the production IP, reboots it
6. Destroys the old VM

Zero downtime.

---

# 5. TSIG Key Management

Ansible generates a TSIG key (`externaldns-key`) via the Technitium API
on every deploy, then writes it to Bitwarden:

- TSIG Name
- TSIG Algorithm
- TSIG Secret

Ansible never retrieves a pre-existing TSIG key — it always generates a
fresh one and overwrites the stored values.

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
- Ansible reads bw.env locally and writes generated secrets to
  Bitwarden — it never fetches secrets from Bitwarden

---

# 8. Summary

This architecture provides:

- Declarative DNS
- Declarative VM lifecycle
- Declarative secrets
- Strict CI/CD validation
- Zero-downtime rebuilds

Everything is automated.
