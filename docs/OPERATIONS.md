# Operations Guide

Daily operator tasks for GitOps DNS.

---

# 1. Validate DNS

    dig @172.16.100.6 SOA
    dig @172.16.100.6 <hostname> A

---

# 2. Add DNS Records

See DNS-QUICKSTART.md.

---

# 3. Rotate TSIG Keys

See TSIG-ROTATION.md.

---

# 4. Rebuild Technitium

`make deploy` alone is a safe no-op once a VM is already live on prod_vm_ip --
vm_id and IP drift are deliberately ignored so a routine apply can't
force-replace or revert the running server. To actually rebuild:

    # Bump the rebuild trigger (any new value works, e.g. increment it)
    # in technitium/terraform/local/terraform.tfvars:
    rebuild_id = "2"

    make deploy

Terraform auto-detects the current production VMID (whichever VM currently
holds prod_vm_ip, via current-prod-vmid.sh) -- no manual old_vm_id tracking
needed between rebuilds. This builds a fresh temp VM, validates DNS on it,
cuts it over to prod_vm_ip, stops the detected old VM, then destroys it
natively. Leave `old_vm_id` commented out in terraform.tfvars; only set it
to override auto-detection with a specific VMID.

---

# 5. Check CI/CD

Gitea validates:

- Syntax
- Serial increments
- Drift
- Intentional changes

---

# 6. Check VMID Allocation

    technitium/terraform/scripts/next-vmid.sh

---

# 7. Check Secrets

    secrets/bw.env.sample

Real secrets live in Proxmox:

    /etc/pve/technitium/bw.env

---

# 8. Summary

Operators manage:

- DNS changes
- TSIG rotation
- VM rebuilds
- CI/CD validation
- Secret hygiene
