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

    make deploy

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
