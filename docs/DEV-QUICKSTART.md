# Developer Quickstart

This guide helps developers contribute safely.

---

# 1. Clone Repo

    git clone <repo>
    cd <repo>

---

# 2. Make DNS Changes

Edit:

    dns/zones/<domain>.zone

---

# 3. Update Serial

    dns/scripts/update-serials.sh

---

# 4. Validate

    make validate-zones

---

# 5. Commit + Push

CI/CD validates strict mode.

---

# 6. Deploy

    make deploy

---

# Summary

Developers only modify:

- Zone files
- Secret IDs (never secrets)
