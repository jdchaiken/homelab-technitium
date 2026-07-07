# Developer Quickstart

This guide helps developers contribute safely to the GitOps DNS platform.

---

# 1. Clone Repo

    git clone <repo>
    cd <repo>

Install Git hooks (required):

    make install-hooks
    make verify-hooks

---

# 2. Make DNS Changes

Edit zone files:

    dns/zones/<domain>.zone

Only modify DNS records and SOA serials.

---

# 3. Update Serial

Run the serial update script:

    dns/scripts/update-serials.sh

This ensures all modified zones have correctly incremented SOA serials.

---

# 4. Validate Zones

    make validate-zones

This runs named-checkzone against all zone files.

---

# 5. Commit and Push

Git hooks will block:
- secrets
- .env files
- .tfvars
- .tfstate
- TSIG secrets
- SSH private keys
- invalid commit messages

CI/CD enforces strict zone validation and SOA rules.

---

# 6. Deploy

    make deploy

This performs a zero-downtime rebuild of the Technitium DNS server.

---

# Summary

Developers only modify:

- DNS zone files
- Secret IDs (never secrets)
- Terraform variables when required

Always ensure Git hooks remain installed and up to date:

    make verify-hooks
