# Operations Guide

Daily operator tasks for GitOps DNS.

---

# 1. Validate DNS

    dig @172.16.100.6 SOA
    dig @172.16.100.6 <hostname> A

---

# 2. Add DNS Records

See DNS-QUICKSTART.md.

---

# 3. Rotate TSIG Keys

See TSIG-ROTATION.md.

---

# 4. Rebuild Technitium

`make deploy` alone is a safe no-op once a VM is already live on prod_vm_ip --
vm_id and IP drift are deliberately ignored so a routine apply can't
force-replace or revert the running server. To actually rebuild:

    # Bump the rebuild trigger (any new value works, e.g. increment it)
    # in technitium/terraform/local/terraform.tfvars:
    rebuild_id = "2"

    make deploy

Terraform auto-detects the current production VMID (whichever VM currently
holds prod_vm_ip, via current-prod-vmid.sh) -- no manual old_vm_id tracking
needed between rebuilds. This builds a fresh temp VM, validates DNS on it,
cuts it over to prod_vm_ip, stops the detected old VM, then destroys it
natively. Leave `old_vm_id` commented out in terraform.tfvars; only set it
to override auto-detection with a specific VMID.

---

# 5. Staging Environment

A second, parallel deploy target for testing Terraform/Ansible changes
before trusting them against real production. Same pipeline, same Proxmox
cluster, different IPs/hostname/state:

    make deploy-staging     # build/rebuild staging
    make destroy-staging    # tear it down entirely

Setup (one-time): copy
`technitium/terraform/staging.tfvars.example` to
`technitium/terraform/local/staging.tfvars` and fill in real credentials.

Staging runs at `172.16.100.10` (temp) / `172.16.100.11` (its "production"
analog, named `ns1-staging`), identifies as `ns1-staging.example.com`,
and issues certs from **Let's Encrypt's staging directory** -- untrusted by
browsers, but with no risk to production's real rate limits no matter how
many times it's rebuilt.

Three things are deliberately isolated from production, not shared:

- **TSIG key**: staging has no separate ExternalDNS/OPNsense to test DDNS
  against, so it fetches production's real TSIG key from Bitwarden by name
  and reuses it, rather than generating (and polluting Bitwarden with) a
  new one every rebuild.
- **NFS cert storage**: staging's persisted Let's Encrypt state lives in a
  separate subfolder (`technitium-staging/`) on the same NFS export as
  production's (`technitium/`) -- same share, can't collide.
- **Terraform state**: staging deploys to its own `staging` workspace, kept
  separate from production's `default` workspace. Both `deploy` and
  `deploy-staging` explicitly select their workspace before applying, so
  running one after the other can never silently apply against the wrong
  environment.

`technitium-ansible-api-key` is the one thing staging never touches at all
(skipped, not shared) -- nothing in this repo reads it back
programmatically, so there's no reason for staging to write its own copy.

---

# 6. Check CI/CD

Gitea validates:

- Syntax
- Serial increments
- Drift
- Intentional changes

---

# 7. Check VMID Allocation

    technitium/terraform/scripts/next-vmid.sh

---

# 8. Check Secrets

    secrets/bw.env.sample

Real secrets live in Proxmox:

    /etc/pve/technitium/bw.env

---

# 9. Check Proxmox DNS Sync

Publishes an A record in Technitium for every running Proxmox VM/CT
(name + IP), on a 15-minute systemd timer on `pm_node` -- see
`technitium/terraform/scripts/proxmox-dns-sync.sh` for the full design
notes and `INSTALL.md` for (re-)deployment. Runs from `pm_node` only,
never every node -- it's a periodic job, not something Terraform invokes
on demand, and running it from multiple nodes would race itself.

Check status / trigger a run by hand:

    ssh root@<pm_node> systemctl status proxmox-dns-sync.timer
    ssh root@<pm_node> systemctl start proxmox-dns-sync.service   # runs once, immediately
    ssh root@<pm_node> journalctl -u proxmox-dns-sync.service -n 60

Only ever touches records it created itself, tracked in a local state
file (`/opt/infra/technitium/proxmox-dns-sync-state.json`) -- never
touches manually-created records or records from ExternalDNS/Kea. VMs
whose name collides with a manually-maintained zone-file entry (`pve01-
04`, `docker01-03`, `nas01`, `omada`, `postgresql` as of this writing)
are managed by both until those entries are removed from the zone file --
the sync's writes win day-to-day, the zone file's import wins at the next
`make deploy`.

---

# 10. Summary

Operators manage:

- DNS changes
- TSIG rotation
- VM rebuilds
- Staging test deploys
- CI/CD validation
- Secret hygiene
- Proxmox DNS sync (largely self-managing once deployed)
