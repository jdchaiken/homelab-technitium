# DNS Zones & Validation

This directory contains all authoritative DNS data and validation logic.

---

## Structure

    dns/
      zones/        # Authoritative zone files
      scripts/      # Validation + serial tools

Gitea workflows live under .gitea/workflows/ at the repo root, not here.

---

## Zone Files

Zone files live under:

    dns/zones/

Each zone must:

- Contain a valid SOA record
- Use YYYYMMDDNN serial format
- Pass strict CI/CD validation

---

## Scripts

### Syntax validation

    make validate-zones

Runs `named-checkzone` on all zones.

### Strict validation

    dns/scripts/zone-diff-strict.sh

Enforces:

- SOA serial increment
- No accidental changes
- No drift from main
- No malformed SOA
- No accidental deletions/additions

### Serial auto-increment

    dns/scripts/update-serials.sh

Updates SOA serials using YYYYMMDDNN format.

### TSIG rotation helper

    dns/scripts/rotate-tsig.sh

Documents safe TSIG rotation workflow.

---

## CI/CD

The Gitea workflow lives at:

    .gitea/workflows/zone-check.yaml

It runs:

- Syntax validation
- Strict diff checker
- Serial enforcement

CI/CD must pass before deployment.

---

## Adding DNS Records

1. Edit zone file
2. Run:

       dns/scripts/update-serials.sh

3. Commit + push
4. CI/CD validates
5. Deploy:

       make deploy

---

## Summary

This directory contains:

- Authoritative DNS data
- Validation logic
- CI/CD workflows
- Serial management
- TSIG rotation helpers

Everything is declarative.
