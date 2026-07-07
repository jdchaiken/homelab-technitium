# Contributing to GitOps DNS

This repository manages authoritative DNS for internal domains. All changes must
follow strict rules to ensure safety and correctness.

---

# 1. Requirements

Before contributing:

- Understand DNS zone syntax
- Understand SOA serial rules (YYYYMMDDNN)
- Understand GitOps workflow
- Understand CI/CD validation

---

# 2. Adding DNS Records

1. Edit zone file under:

       dns/zones/

2. Run:

       dns/scripts/update-serials.sh

3. Validate:

       make validate-zones

4. Commit + push

5. CI/CD validates strict mode

6. Deploy:

       make deploy

---

# 3. Changing DNS Records

Same workflow as adding records.

---

# 4. Deleting DNS Records

Allowed, but must:

- Increment SOA serial
- Pass strict diff checker
- Be intentional

---

# 5. TSIG Key Changes

See TSIG-ROTATION.md.

---

# 6. Prohibited Actions

- Never commit secrets
- Never modify cloud-init directly
- Never modify Terraform VMID logic
- Never bypass CI/CD
- Never manually edit Technitium UI (Git is source of truth)

---

# 7. Summary

All DNS changes must be:

- Declarative
- Intentional
- Validated
- Reproducible
- Safe
