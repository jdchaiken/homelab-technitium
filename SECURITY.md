# Security Guide

This system is designed to prevent accidental outages and protect secrets.

---

# 1. Secret Handling

### Never store secrets in Git.

Real secrets live in:

    /etc/pve/technitium/bw.env

bw.env holds the Bitwarden service account token/org/project plus
TECHNITIUM_ADMIN_PASSWORD (the password Ansible sets on Technitium's
default `admin` account on first boot).

Bitwarden stores what Ansible generates and writes there:

- Technitium Ansible API key
- TSIG Name
- TSIG Algorithm
- TSIG Secret

Ansible never retrieves secrets from Bitwarden — it only reads bw.env
locally and writes the secrets it generates.

---

# 2. CI/CD Enforcement

CI/CD prevents:

- Accidental zone edits
- Missing serial increments
- Drift from main
- Malformed SOA
- Accidental deletions/additions

---

# 3. VM Lifecycle Safety

Terraform ensures:

- VMID uniqueness
- Temporary VM validation
- Zero-downtime cutover
- Old VM destruction

---

# 4. Proxmox Security

Bitwarden credentials stored securely:

    chmod 600 /etc/pve/technitium/bw.env

---

# 5. DNS Safety

Strict mode prevents:

- Unintentional changes
- Serial regressions
- Syntax errors
- Drift

---

# 6. Summary

Security principles:

- Secrets external
- Git declarative
- CI/CD enforced
- Terraform controlled
- Zero downtime
