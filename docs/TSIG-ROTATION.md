# TSIG Key Rotation

TSIG keys authenticate RFC2136 DNS updates from ExternalDNS.

Rotation is a side effect of the normal zero-downtime rebuild — there is
no separate manual rotation procedure.

---

# 1. Rebuild Technitium

    make deploy

This builds a brand-new VM. `configure-technitium.yaml` runs on it fresh
and automatically:

- Generates a new TSIG key named `externaldns-key` (hmac-sha256) via the
  Technitium API
- Overwrites the following secrets in Bitwarden with the new values:

      externaldns-tsig-name
      externaldns-tsig-algorithm
      externaldns-tsig-secret

Nothing needs to be created in the Technitium UI, and there are no
Secret IDs hardcoded in the playbook to edit — the key name is fixed
(`externaldns-key`) and the values are pushed to Bitwarden under fixed
secret names every run.

---

# 2. Update ExternalDNS

Point ExternalDNS at the new secret values in Bitwarden
(`externaldns-tsig-name`/`externaldns-tsig-algorithm`/`externaldns-tsig-secret`).

---

# 3. Verify

    dig @PROD_VM_IP SOA

Confirm ExternalDNS updates are still accepted with the new key.

---

# Summary

TSIG rotation is:

1. `make deploy` (rebuilds the VM, generates and stores a new TSIG key)
2. Point ExternalDNS at the refreshed Bitwarden secret values
3. Verify

Zero downtime.
