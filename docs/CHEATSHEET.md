# Operator Cheat Sheet

Quick reference for daily operations.

---

# Validate DNS

    dig @172.16.100.6 SOA
    dig @172.16.100.6 <hostname> A

---

# Add DNS Records

    edit dns/zones/<domain>.zone
    dns/scripts/update-serials.sh
    make validate-zones
    git commit -am "DNS update"
    git push
    make deploy

---

# Rotate TSIG

    create new TSIG in Technitium
    store in Bitwarden
    update Secret IDs
    git commit
    git push
    make deploy

---

# Rebuild VM

    make deploy

---

# Check VMID

    technitium/terraform/scripts/next-vmid.sh

---

# Check CI/CD

Gitea → Pipelines → DNS Validation

---

# Summary

Everything is declarative.
