# DNS Quickstart

This guide explains how to add or modify DNS records.

---

# 1. Edit Zone File

Edit:

    dns/zones/<domain>.zone

Add or modify records.

---

# 2. Update Serial

Run:

    dns/scripts/update-serials.sh

This updates SOA serial using YYYYMMDDNN format.

---

# 3. Validate Syntax

Run:

    make validate-zones

---

# 4. Commit + Push

CI/CD will validate:

- Syntax
- Serial increment
- Drift
- Intentional changes

---

# 5. Deploy

Run:

    make deploy

Terraform will:

- Create new VM
- Configure Technitium
- Validate DNS
- Swap IPs
- Destroy old VM

Zero downtime.

---

# Summary

Adding DNS records is:

1. Edit zone
2. Update serial
3. Validate
4. Commit + push
5. Deploy
