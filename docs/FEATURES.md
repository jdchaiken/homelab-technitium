# Features & Technology Integration

What this project actually touches, and why each integration is there.
Everything below is implemented and live, not aspirational — see the
linked docs/scripts for the real thing.

---

# 1. At a Glance

| Technology | Role | Doc |
|---|---|---|
| Technitium DNS Server | Authoritative + conditional-forwarding DNS core | ARCHITECTURE.md |
| Proxmox VE | Blue-green VM lifecycle, cluster resource introspection | ../INSTALL.md, ../VMID.md |
| Terraform | Declarative VM lifecycle, staging isolation via workspaces | ARCHITECTURE.md |
| Ansible | Declarative Technitium configuration | technitium/README.md |
| Bitwarden Secrets Manager | Central secret store, machine-account automation | SECRETS-FLOW.md |
| OPNsense + Kea DHCP | DHCP-lease-to-DNS automation via authenticated dynamic updates | ../technitium/ansible/APPS.md |
| ExternalDNS (Kubernetes) | Ingress/Service-to-DNS automation via authenticated dynamic updates | — |
| External Secrets Operator | Bitwarden -> Kubernetes Secret sync for ExternalDNS | — |
| Gitea Actions | CI/CD zone validation + secret scanning | CI-PIPELINE.md |
| Let's Encrypt / ACME | Automated TLS for DoT/DoH/DoH3/DoQ | — |
| PostgreSQL | Query log storage backend | ../technitium/ansible/APPS.md |
| systemd + pmxcfs | Cluster-resilient periodic Proxmox DNS sync | OPERATIONS.md § 9 |

---

# 2. Technitium DNS Server

The authoritative DNS core for `example.com`, `example.net`, and
`storage.example.com`, run as a primary/secondary pair (`ns1`/`ns2`)
for redundancy.

**Value:** a full-featured, API-driven DNS server (DNSSEC, DoT/DoH/DoH3/
DoQ, RFC2136 dynamic updates, DNS Apps) that's entirely configurable
over HTTP -- everything in this repo is built by scripting that API, not
editing config files by hand on the box.

**Split-DNS via Conditional Forwarder zones:** each zone is a Technitium
"Forwarder" zone type, not Primary -- it answers every record it hosts
authoritatively, but anything undefined falls through to an upstream
resolver (Unbound, via OPNsense) instead of NXDOMAIN. This is what lets
externally-hosted names coexist with internally-authoritative ones in the
same zone, without a second, disconnected DNS setup.

---

# 3. Proxmox VE

Every Technitium node is a Proxmox VM, built and torn down entirely by
Terraform -- no manually-clicked VMs.

- **Zero-downtime rebuilds:** Terraform clones a template into a
  temporary VM, waits for Technitium to answer DNS on the temp IP, then
  cuts over (stop old, re-IP new, reboot) -- see ARCHITECTURE.md § 4.
- **Cross-node cloning:** the template lives on one node; VMs get built
  on whichever node each Terraform variable targets, confirmed against
  the provider's own schema rather than guessed.
- **Cluster-wide VMID/production detection:** `next-vmid.sh` and
  `current-prod-vmid.sh` query `pvesh` cluster-wide so Terraform never
  needs a hardcoded VMID or manually-tracked "which VM is production"
  state.

**Value:** infrastructure that rebuilds itself from a git commit, with
no SSH-and-click steps, and no single node being a hard dependency for
where a VM can live.

---

# 4. Terraform

Owns the full VM lifecycle (see § 3) plus environment isolation:

- **Staging workspace:** `make deploy-staging` exercises the identical
  pipeline against throwaway infrastructure (separate IPs/hostname,
  Let's Encrypt *staging* ACME server so real rate limits are never at
  risk, production's real TSIG key reused read-only) before anything
  touches production.
- **`create_before_destroy` + `replace_triggered_by`:** rebuilds are
  additive-then-subtractive, never destructive-first -- the old VM stays
  serving traffic until the new one is confirmed healthy.

**Value:** the same apply path is used for a disposable test as for
production, so "it worked in staging" actually means something.

---

# 5. Ansible

Configures each freshly-built Technitium VM entirely through its REST
API -- zones, TSIG, dynamic-update policy, TLS, DNS Apps -- run locally
on the VM by cloud-init, never invoked remotely.

**Value:** every Technitium setting this project cares about is
version-controlled and reproducible, not a snapshot of manual clicks in
the web console.

---

# 6. Bitwarden Secrets Manager

The single source of truth for generated secrets (TSIG keys, Technitium
API tokens) and operator-supplied ones (Cloudflare API token, OPNsense
API credentials, PostgreSQL connection info) -- accessed via the `bws`
CLI machine-account, never the interactive vault.

- **Idempotent upsert, not blind create:** `bws secret create` has no
  update-if-exists semantics, so a naive implementation would leave a
  new duplicate secret behind on every single rebuild. `upsert_secret()`
  finds-and-updates the existing entry by name instead, self-healing an
  existing pile of duplicates down to one the next time it runs.
- **JSON-blob secrets for related config:** `TECHNITIUM_QUERYLOGS_PG_CONFIG`,
  `OPNSENSE_API_CONFIG`, `TECHNITIUM_SSO_CONFIG` each bundle a whole
  connection config into one secret lookup instead of scattering
  individual fields across bw.env.

**Value:** no secret is ever committed to git, no secret has more than
one live copy, and every consumer (Ansible, the Proxmox DNS sync,
Kubernetes) reads from the same place.

---

# 7. OPNsense + Kea DHCP

DHCP leases register themselves into Technitium automatically, via
Kea's DHCP-DDNS (D2) daemon sending authenticated RFC2136 updates.

**Value:** devices that just request a DHCP lease show up in DNS with no
manual record and no separate agent -- the same mechanism ExternalDNS
provides for Kubernetes, but for the physical/DHCP side of the network.
Debugged and fixed end-to-end this project, catching three independent,
non-obvious failure modes along the way (documented in
`technitium/ansible/APPS.md` and
`configure-technitium.yaml`'s own comments, not just fixed silently):

1. Kea's D2 daemon must listen on `127.0.0.1` (its own local address),
   not the target DNS server's IP -- an easy mix-up since the two
   settings sit next to each other in OPNsense's UI.
2. Every subnet needs `ddns_qualifying_suffix` set, or clients that
   don't self-supply a full FQDN get silently dropped before ever
   reaching Technitium.
3. Technitium's dynamic-update policy must explicitly allow `DHCID`
   records, not just `A`/`AAAA` -- Kea's default conflict-resolution mode
   sends a DHCID record in the same atomic transaction as the address
   record, and one disallowed type in a DNS UPDATE transaction refuses
   the whole thing.

---

# 8. ExternalDNS (Kubernetes) + External Secrets Operator

Kubernetes Ingress/HTTPRoute/Service objects publish their own DNS
records into Technitium via the `rfc2136` ExternalDNS provider, secured
with the same TSIG key Bitwarden already holds. The `ExternalSecret`
custom resource keeps that key in sync from Bitwarden into a Kubernetes
`Secret` on its own schedule.

**Value:** application deployment and DNS registration are the same git
push -- no separate "add a DNS record" step for anything running in the
cluster. (Consuming services still need a *restart* to pick up a rotated
secret from an updated `Secret` object if they read it via environment
variable rather than a mounted file -- a general Kubernetes behavior,
not specific to this setup, but worth knowing when a rotation doesn't
seem to have "taken".)

---

# 9. Gitea Actions CI/CD

Every push to a zone file runs through validation before it's trusted:

- `named-checkzone` syntax validation
- Strict diff check against the previous commit
- SOA serial-increment enforcement (only when that zone actually changed)
- `git-secrets` + `detect-secrets` scanning

**Value:** a broken zone file, a missing serial bump, or an accidentally
committed credential gets caught in CI, not after it's already live.

---

# 10. Let's Encrypt / ACME (via Cloudflare DNS-01)

Technitium's DoT/DoH/DoH3/DoQ listeners get a real, auto-renewing TLS
certificate, issued via Cloudflare's DNS-01 challenge (no port 80/443
exposure needed for issuance). Staging deploys use Let's Encrypt's own
*staging* ACME server specifically so pipeline testing can never trip
production rate limits.

---

# 11. Technitium DNS Apps

Optional server-side modules, installed and configured the same way
everything else is -- through the API, from Ansible:

- **Auto PTR** -- synthesizes PTR answers from existing A/AAAA records,
  no reverse zone needed at all.
- **Weighted Round Robin** -- weighted answer distribution across
  multiple IPs for a single name.
- **Query Logs (PostgreSQL)** -- ships query logs to Postgres instead of
  local storage, config pulled from a single Bitwarden JSON secret.

---

# 12. systemd + Proxmox Cluster Filesystem (pmxcfs)

`proxmox-dns-sync` publishes a DNS record for every running Proxmox
VM/CT automatically, so infrastructure hosts don't need hand-maintained
zone-file entries. Runs on **all four** cluster nodes via a systemd
timer, coordinated by a lock file -- both the script and its state live
in `/etc/pve/technitium/` (pmxcfs, replicated cluster-wide by Proxmox
itself), so there's no single node whose failure stops the sync. If the
node currently winning the lock goes down, the next timer fire on any
surviving node picks it up within one cycle.

**Value:** the same "no manual DNS records" guarantee ExternalDNS gives
Kubernetes and Kea gives DHCP, extended to the Proxmox layer itself --
and resilient to a single node failure by construction, not by accident.
