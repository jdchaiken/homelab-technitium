# Technitium DNS Server – GitOps Deployment

This directory contains all automation required to deploy Technitium DNS Server
in a fully declarative GitOps workflow.

---

## Structure

    technitium/
      ansible/        # install + configure playbooks
      cloud-init/     # technitium-user.yaml.example (real copy: local/, gitignored)
      terraform/      # VM lifecycle automation
        scripts/      # VMID allocator

---

## Ansible

Located under:

    technitium/ansible/

### install-technitium.yaml
Installs Technitium DNS Server.

### configure-technitium.yaml
Bootstraps Technitium's default admin account, mints a permanent API
key, then configures:

- TSIG keys (generated via the Technitium API, written to Bitwarden)
- Upstream resolvers
- ACLs
- Logging
- Zone imports
- RFC2136 support

No manual API key creation is required — see INSTALL.md.

---

## Cloud-init

Tracked template:

    technitium/cloud-init/technitium-user.yaml.example

Contains a real SSH key, so it's not tracked directly -- copy the example to
`technitium/cloud-init/local/technitium-user.yaml` (gitignored) and fill in
your own key. `make deploy` syncs that local copy to Proxmox automatically.

Cloud-init:

- Clones the Git repo
- Copies bw.env from the Proxmox host
- Runs Ansible install + configure locally on the VM

---

## Terraform

Located under:

    technitium/terraform/

Terraform automates:

- VM creation
- VMID allocation
- Cloud-init provisioning
- DNS readiness checks
- Zero-downtime cutover
- Old VM destruction

### VMID allocator

    technitium/terraform/scripts/next-vmid.sh

Returns the highest VMID in use within the 4000–4999 GitOps range, plus 1.

### Current production VMID detection

    technitium/terraform/scripts/current-prod-vmid.sh

Finds whichever VM in that same range currently holds `prod_vm_ip`, so
Terraform can auto-detect and stop/destroy the old VM during cutover
without operators having to hand-maintain `old_vm_id`. See VMID.md.

### Proxmox DNS sync

    technitium/terraform/scripts/proxmox-dns-sync.sh

Publishes an A record in Technitium for every running Proxmox VM/CT,
keyed off Proxmox's own name/IP -- runs on a 15-minute systemd timer on
**all four nodes**, coordinated by a lock file so only one actually runs
at a time. Unlike the two scripts above (copied per-node via `clush`),
the script itself lives in `/etc/pve/technitium/` -- pmxcfs, replicated
cluster-wide automatically, so there's exactly one copy to keep current
regardless of which/how many nodes run it. Deployment is still manual,
see INSTALL.md. See OPERATIONS.md § 9 for day-to-day operation and its
reconciliation/safety model.

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
