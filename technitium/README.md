# Technitium DNS Server – GitOps Deployment

This directory contains all automation required to deploy Technitium DNS Server
in a fully declarative GitOps workflow.

---

## Structure

    technitium/
      ansible/        # install + configure playbooks
      cloud-init/     # technitium-user.yaml
      terraform/      # VM lifecycle automation
        scripts/      # VMID allocator

---

## Ansible

Located under:

    technitium/ansible/

### install-technitium.yaml
Installs Technitium DNS Server.

### configure-technitium.yaml
Configures:

- TSIG keys (via Bitwarden)
- Upstream resolvers
- ACLs
- Logging
- Zone imports
- RFC2136 support

---

## Cloud-init

Located under:

    technitium/cloud-init/technitium-user.yaml

Cloud-init:

- Clones the Git repo
- Copies Bitwarden env
- Exports Bitwarden credentials
- Runs Ansible install + configure

---

## Terraform

Located under:

    technitium/terraform/

Terraform automates:

- VM creation
- VMID allocation (4000–4999)
- Cloud-init provisioning
- DNS readiness checks
- Zero-downtime cutover
- Old VM destruction

### VMID allocator

    technitium/terraform/scripts/next-vmid.sh

Finds next available VMID in 4000–4999.

---

## Zero-Downtime Workflow

1. Create new VM at 172.16.100.7
2. Configure via cloud-init + Ansible
3. Validate DNS
4. Stop old VM
5. Swap IPs
6. Destroy old VM

DNS never goes offline.

---

## Deployment

Run:

    make deploy

---

## Summary

This directory contains:

- Full Technitium automation
- Cloud-init bootstrap
- Ansible configuration
- Terraform VM lifecycle
- Zero-downtime rebuild logic

Everything is declarative.
