# TSIG Key Rotation

TSIG keys authenticate RFC2136 DNS updates from ExternalDNS.

Rotation uses the same GitOps workflow as DNS changes.

---

# 1. Create New TSIG Key

In Technitium UI:

1. Settings → TSIG Keys → Add
2. Name: externaldns-key
3. Algorithm: hmac-sha256
4. Secret: Generate
5. Save

---

# 2. Store in Bitwarden

Create three secrets:

    externaldns-tsig-name
    externaldns-tsig-algorithm
    externaldns-tsig-secret

Copy Secret IDs.

---

# 3. Update Ansible

Edit:

    technitium/ansible/configure-technitium.yaml

Set new Secret IDs.

---

# 4. Commit + Push

CI/CD validates.

---

# 5. Deploy

Run:

    make deploy

Terraform rebuilds Technitium with new TSIG key.

Zero downtime.

---

# Summary

TSIG rotation is:

1. Create key
2. Store in Bitwarden
3. Update Secret IDs
4. Commit + push
5. Deploy
