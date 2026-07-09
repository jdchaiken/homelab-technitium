# DNS Outage Runbook

This runbook describes how to diagnose and resolve DNS outages.

---

# 1. Check Technitium Health

    systemctl status technitium.service

If not running:

    systemctl restart technitium.service

---

# 2. Check DNS Resolution

    dig @172.16.100.6 SOA
    dig @172.16.100.6 <hostname> A

If no response:

- Check VM status in Proxmox
- Check network connectivity

---

# 3. Check Logs

    journalctl -u technitium.service -n 100

Look for:

- Zone import errors
- TSIG errors
- Bind errors

---

# 4. Check CI/CD

If CI/CD failed:

- Serial not incremented
- Drift detected
- Syntax error

Fix zone files and redeploy.

---

# 5. Rebuild Technitium

If VM is corrupted:

    make deploy

This performs a zero-downtime rebuild.

---

# 6. Check TSIG

If ExternalDNS fails:

- Rotate the TSIG key by running `make deploy` (see docs/TSIG-ROTATION.md)
- Point ExternalDNS at the refreshed Bitwarden secret values

---

# 7. Escalation

If outage persists:

- Check Proxmox logs
- Check network ACLs
- Check upstream resolvers

---

# Summary

This runbook covers:

- DNS health checks
- VM checks
- CI/CD checks
- TSIG checks
- Zero-downtime rebuilds
