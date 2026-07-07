# GitOps DNS Infrastructure

This repository implements a fully declarative, GitOps-managed DNS system using:

- Technitium DNS Server (authoritative)
- Terraform (VM lifecycle + zero-downtime rebuilds)
- Proxmox (virtualization)
- Cloud-init (bootstrap)
- Ansible (configuration)
- Bitwarden Secrets Manager (TSIG + API secrets)
- Gitea Actions (CI/CD validation)
- Strict DNS policy enforcement (SOA increments, drift detection)

Everything is reproducible. Destroy the VM, run `make deploy`, and the DNS server
is rebuilt exactly from Git + Bitwarden.

---

## Repository Structure

    dns/
      zones/          # Authoritative zone files
      scripts/        # zone-diff, strict checker, serial updater
      ci/             # Gitea workflows

    technitium/
      ansible/        # install + configure playbooks
      cloud-init/     # technitium-user.yaml
      terraform/      # VM lifecycle automation
        scripts/      # VMID allocator

    secrets/          # Bitwarden env templates

    Makefile          # Local operator commands
    INSTALL.md        # Full installation guide
    POST-INSTALL.md   # Post-deployment tasks
    PROXMOX_VM_TEMPLATE.md
    README.md         # This file

---

## GitOps Workflow

1. Edit zone files under `dns/zones/`
2. Run strict validation:
       dns/scripts/zone-diff-strict.sh
3. Commit + push
4. CI/CD validates:
       - Syntax
       - Serial increments
       - Drift
5. Deploy:
       make deploy

Terraform:

- Allocates VMID (4000–4999)
- Creates temporary VM (172.16.100.7)
- Applies cloud-init
- Runs Ansible
- Validates DNS
- Shuts down old VM
- Swaps IPs
- Destroys old VM

Zero downtime.

---

## TSIG Key Management

TSIG keys are stored in Bitwarden Secrets Manager.

Ansible fetches:

- TSIG Name
- TSIG Algorithm
- TSIG Secret

Using Secret IDs.

TSIG rotation uses the same GitOps rebuild workflow.

---

## VMID Allocation

GitOps-managed VMIDs live in the 4000–4999 range.

Script:

    technitium/terraform/scripts/next-vmid.sh

Finds the next available VMID.

If all are used, wraps back to 4000.

---

## Zero-Downtime Rebuild

Terraform performs:

1. Create new VM at 172.16.100.7
2. Configure via cloud-init + Ansible
3. Validate DNS
4. Stop old VM
5. Swap IPs
6. Destroy old VM

DNS never goes offline.

---

## Commands

Validate zones:

    make validate-zones

Strict validation:

    dns/scripts/zone-diff-strict.sh

Deploy:

    make deploy

Update serials:

    dns/scripts/update-serials.sh

Rotate TSIG:

    dns/scripts/rotate-tsig.sh

---

## Summary

This repository provides:

- Declarative DNS
- Declarative VM lifecycle
- Declarative secrets
- Declarative configuration
- Strict CI/CD validation
- Zero-downtime rebuilds

Everything is automated.
Everything is reproducible.
Everything is safe.
