# AI.md

Context and working rules for an AI assistant operating in this repo,
written from what actually broke and got fixed while building it. Read
this before making changes -- it'll save you from re-discovering bugs
that already cost real debugging time once.

For what this repo *is*, see [README.md](README.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). For the full doc catalog,
start at [docs/INDEX.md](docs/INDEX.md). For a value-oriented tour of
every technology this project touches, see
[docs/FEATURES.md](docs/FEATURES.md).

---

# 1. The One Rule That Matters Most

**Never guess an API field name, endpoint, or config shape. Verify it
against real source or a live instance, every time.**

This project talks to three different APIs that don't publish complete,
trustworthy docs (Technitium's REST API, OPNsense's REST API, Proxmox's
REST API), plus a CLI (`bws`) with sparse docs. Every non-trivial bug
found in this codebase's history traces back to one of two things:
someone guessed a field name that turned out wrong, or assumed an API's
behavior without checking. The fix was always the same: pull the actual
source and read it, or hit the live API and look at the real response.

**How to verify Technitium's API:** its full source is public --
`gh api repos/TechnitiumSoftware/DnsServer/contents/<path>` (e.g.
`DnsServerCore/WebServiceZonesApi.cs`, `WebServiceAppsApi.cs`,
`DnsServerCore/Dns/DnsServer.cs`, `DnsServerCore/Dns/Zones/*.cs`) --
`.content` is base64, pipe through `base64 -d`. Grep for the C# method
name matching the endpoint you're about to call and read what it
actually does with its parameters, not what the name implies.

**How to verify OPNsense's API:** same approach against
`gh api repos/opnsense/core/contents/<path>` -- controllers live under
`src/opnsense/mvc/app/controllers/OPNsense/<Module>/Api/`, models
(field names, defaults, validation) under
`src/opnsense/mvc/app/models/OPNsense/<Module>/<Module>.xml`. The base
`ApiMutableModelControllerBase.php`/`ApiControllerBase.php` classes
explain the generic `get`/`set`/`setBase`/`searchBase` conventions
every module inherits.

**How to verify Proxmox's API:** `pvesh get <path> --output-format json`
directly against a live node tells you the truth faster than any doc.

**If you can't verify live and can't find the source, say so explicitly**
rather than presenting a guess as fact. This codebase's comments are
full of "confirmed live" / "verified against source, not guessed" /
"NOT live-tested -- confirm before trusting" annotations for exactly
this reason -- keep that discipline up. If you ship something unverified,
say so in the commit and in-file, the way the rest of this repo does.

---

# 2. Repository Map

```
technitium/terraform/       Terraform VM lifecycle
  main.tf                     ns1 (Primary/Forwarder), blue-green rebuild
  ns2.tf                      ns2 (Secondary Forwarder), independent trigger
  variables.tf                 all tfvars, prod + ns2_* + staging
  scripts/                     shell helpers deployed onto Proxmox nodes
                                (see § 5 -- these are NOT auto-deployed)
  local/terraform.tfvars       gitignored, real operator values

technitium/ansible/          Ansible playbooks, run locally on the VM by
                              cloud-init (never invoked remotely)
  install-technitium.yaml      installs Technitium + bws CLI
  configure-technitium.yaml    ns1: zones, TSIG, dynamic updates, Bitwarden
  configure-technitium-secondary.yaml   ns2: Secondary Forwarder zones
  configure-technitium-tls.yaml         ACME cert via Cloudflare DNS-01
  configure-technitium-apps.yaml        DNS Apps + SSO + OPNsense sync
                                (mostly commented-out scaffolds -- see
                                docs/TODO.md item 2 for what's still
                                unscaffolded, and technitium/ansible/APPS.md
                                for what each enabled one actually does)

technitium/cloud-init/        local/*.yaml gitignored (real SSH key etc),
                               *.yaml.example tracked as templates

dns/zones/*.zone              Source of truth for STATIC DNS records.
                               Records covered by proxmox-dns-sync.sh
                               (technitium/terraform/scripts/) should NOT
                               also be manually maintained here -- see
                               that script's own header comment for what
                               it actually covers before adding entries.
dns/scripts/                  validate-zones, update-serials, zone-diff,
                               rotate-tsig (docs only, doesn't rotate)

secrets/bw.env.sample         Every secret this project needs, documented.
                               Real file lives OUTSIDE git, at
                               /etc/pve/technitium/bw.env on the Proxmox
                               host (pmxcfs, cluster-replicated).

docs/                         Extensive. Start at docs/INDEX.md.
.gitea/workflows/             CI: zone syntax, strict diff, serial
                               enforcement, secret scanning
```

---

# 3. Hard-Won Gotchas

Each of these cost real debugging time. Don't re-learn them.

## Technitium

- **The JSON response envelope is inconsistent between endpoints.**
  `/user/login` and `/user/createToken` return fields flat
  (`.json.token`). `/apps/config/get` wraps its field under `.json.
  response.config`. This is not predictable from the endpoint's shape --
  check the actual live response before writing the Jinja/jq path that
  reads it. Getting this wrong doesn't fail loudly; it crashes with
  "object has no attribute X", which is at least loud, but only once
  the task actually runs with `no_log: false` where you can see it.
- **`zones/create` with a zoneFile attached wipes the zone's own NS/FWD
  record before importing the file's content**, then re-adds NS if the
  file has its own NS records -- but a Forwarder zone's FWD record isn't
  a file-representable record type, so it has to be re-added in a
  separate follow-up call after import, every time.
- **`zones/import`'s `overwrite=true` only touches records present in
  the imported file.** It does not delete anything absent from the file
  unless you also pass `overwriteZone=true` (default false, and this
  repo's `push-zones.sh` deliberately never sets it). Don't assume
  "import" means "replace the whole zone."
- **`dnssecValidation: true` breaks Conditional Forwarder (split-DNS)
  resolution** for zones you host but were never really delegated from
  the public root -- Technitium's validator treats the missing DS record
  as a possible spoofing attack (`DnssecIndeterminate: Attack detected!`)
  instead of "insecure, skip validation," even with the per-FWD-record
  `dnssecValidation: false` already set. This project runs with global
  DNSSEC validation off, deliberately, for this reason.
- **A Forwarder (Conditional Forwarder) zone must not have local NS
  records for itself, or its FWD-based fallback breaks completely.**
  Confirmed live 2026-07-17: `example.com`/`example.net`/
  `storage.example.com` all had `IN NS ns1.X` / `IN NS ns2.X` records
  (present only because `named-checkzone` requires at least one NS record
  per zone). With those records live, any name not explicitly in the zone
  file -- `home.example.com`, `auth.example.com`, anything hosted on
  Cloudflare -- SERVFAILed instantly (<5ms, the FWD forwarder was never
  even contacted), because Technitium treated the zone as genuinely
  self-delegated and attempted real recursive resolution against its own
  NS records instead of consulting FWD. Deleting the two NS records live
  (`zones/records/delete&type=NS&nameServer=ns1.X`, same for ns2) fixed it
  immediately -- every previously-failing name started resolving correctly
  through the real FWD path. The zone files keep the NS records (for
  `make validate-zones`); `push-zones.sh` and `configure-technitium.yaml`
  (task 11a2) both delete them from the live zone right after every
  import/create. If you ever see instant (not timeout-latency) SERVFAIL
  for a non-local name in one of these zones, check for stray NS records
  first via `zones/records/get?domain=<zone>&zone=<zone>&listZone=false`.
- **`updateSecurityPolicies`'s allowed record types must cover
  everything a client's UPDATE transaction might send, not just the
  record you think of as "the" record.** DNS UPDATE transactions are
  atomic -- Kea's default conflict-resolution mode sends a `DHCID`
  record alongside the `A` record in the same transaction, and one
  disallowed type refuses the whole thing, with no partial application.
- **Zone-transfer's `AllowOnlyZoneNameServers` ACL depends on the zone's
  own NS records existing**, and can't be *explicitly set* on a
  Forwarder zone via the API (throws) -- but a zone constructed with
  that as its inherited default still works fine, since the restriction
  is only enforced on the public setter path. Don't try to "fix" this
  by explicitly setting it; leave it alone.
- **`bws secret create` is not idempotent** -- every call makes a new,
  differently-ID'd entry. Any code that stores a secret needs to be an
  upsert (list, filter by key name client-side, edit the first match,
  delete the rest) -- see `upsert_secret()` in
  `configure-technitium.yaml` for the pattern already in use.
- **The TSIG key regenerates on every ns1 rebuild** -- it's not stable.
  Every downstream consumer (OPNsense's Kea subnets, the Kubernetes
  `ExternalSecret`) can go stale after any ns1 rebuild until it
  independently re-syncs. This is a known, accepted design tradeoff, not
  a bug -- but it means "the TSIG key doesn't match" is the first thing
  to check after any ns1 rebuild, before assuming something is broken.

## Terraform / Proxmox

- **`data.external` results (like `next-vmid.sh`'s output) are
  recomputed on every single `terraform plan`/`apply`.** Never reference
  a `local.X` derived from one of these for anything that needs to point
  at an *already-created* resource's real, stable value -- once a VM
  exists, `next-vmid.sh` will happily return a *different, higher*
  number on the next apply, since the old one is now taken. Reference
  the resource's own attribute instead (e.g.
  `proxmox_virtual_environment_vm.foo.vm_id`), which is protected by
  `ignore_changes` and reads the real value from state. Getting this
  wrong produces a "phantom vmid" that looks like a real VM but isn't --
  `qm set <phantom-id> ...` fails with "Configuration file ... does not
  exist," which is genuinely confusing until you trace it back.
- **Cross-node clone needs `clone.node_name` set to the SOURCE node**,
  separate from the resource's own top-level `node_name` (the target) --
  confirmed against the provider's own schema
  (`terraform providers schema -json`), not guessed.
- **`remote-exec`'s `inline` list is concatenated into ONE script; only
  the last command's exit status is checked.** A failure partway through
  silently continues into the next command unless `"set -e"` is the
  first entry in the list.
- **A VM taking 20+ minutes to build can be completely normal** for a
  given storage backend -- don't assume a long-running apply is stuck
  without independent evidence (e.g. actually checking whether the VM
  exists and is progressing).
- **Leftover temp VMs from a failed deploy cause IP collisions on
  retry** -- both the temp VM and the retry's new temp VM want the same
  temp IP. Check `qm list | grep technitium-temp` (and `-ns2-temp`)
  across all cluster nodes before telling anyone to retry a deploy.
- **`qm`/`pct` are node-local** -- they only work for VMs/CTs actually
  running on the node you invoke them from. For anything cluster-wide,
  use `pvesh get /nodes/<node>/...`, which proxies to the correct node
  regardless of where you run it from.
- **pmxcfs (`/etc/pve/`) has a fixed permission scheme** -- `chmod`
  fails with "Operation not permitted" on anything under there. A script
  stored in cluster storage has to be invoked via `bash <path>`, not the
  execute bit + shebang.

## OPNsense / Kea

- **Kea's DHCP-DDNS (D2) daemon's `server_ip` setting must be
  `127.0.0.1`** (its own local listen address, where `kea-dhcp4` hands
  it internal NameChangeRequests) -- **not** the target DNS server's IP.
  Easy to mix up with the per-subnet `ddns_dns_server` field (which
  *is* the real target), since they sit next to each other in the UI and
  sound like the same thing.
- **Every Kea subnet needs `ddns_qualifying_suffix` set**, or a client
  that doesn't self-supply a fully-qualified hostname (most don't, by
  default) gets its DDNS update silently dropped with "no DNS servers
  match FQDN `<bare-name>`" before it ever reaches Technitium.
- **`setBase()`/`setNodes()`-backed endpoints (most OPNsense `set_*`
  calls) do a partial update** -- POSTing only the fields you want to
  change is safe and won't clobber the rest of the object. Confirmed
  against `ApiMutableModelControllerBase.php` source, not just observed.

## General / Process

- **Never print a secret value to tool output.** Extract into a shell
  variable and compare by hash or boolean match if you need to verify
  it; never `echo`/`cat`/dump a response that contains one. This has
  gone wrong more than once in this project's history from an API call
  that echoed back more than intended (e.g. `settings/get` including
  `tsigKeys[].sharedSecret`, `search_subnet` including
  `ddns_domain_key_secret`) -- assume any "get full config" style
  endpoint might include a secret field, and filter before you look.
- **Auto-mode-style safety gates will block:** direct writes to
  production secrets files, printing/materializing a credential,
  out-of-pipeline production writes that bypass the Ansible/Terraform
  path. If you hit one of these, it's telling you to route the change
  through the actual pipeline (a script, a playbook, a committed file)
  instead of a one-off manual command -- don't look for a workaround.
- **Zone file changes always need a serial bump** -- `make update-zones`
  (or `dns/scripts/update-serials.sh` directly), never hand-edited. CI
  enforces this on every push.
- **`make push-zones` pushes zone-file content live to ns1 without a
  full VM rebuild** and is safe to run any time (it never sets
  `overwriteZone=true`, so it can't delete anything not in the files) --
  useful for testing a zone change without waiting for a rebuild cycle.

---

# 4. Before You Touch Anything: Verification Checklist

- **Validate before committing:** `ansible-playbook --syntax-check`,
  `yamllint` on any changed playbook; `terraform fmt -check` +
  `terraform validate` on any changed Terraform; `make validate-zones`
  on any changed zone file; `shellcheck` on any changed shell script.
- **Test live before trusting, where you can.** This repo's whole
  culture is "confirmed live" over "should work" -- if there's a running
  instance to test against (staging, a temp VM mid-deploy, the live
  OPNsense/Proxmox API), use it before pushing something that claims to
  be fixed.
- **Check for leftover temp VMs** before any deploy retry (§ 3).
- **Re-read the file you're about to edit if you're not sure it still
  matches what you last saw** -- several bugs in this project's history
  came from editing based on a stale mental model of a file's content
  after someone else (or a background process) touched it.
- **If a change affects a manually-deployed script** (anything under
  `technitium/terraform/scripts/` -- these are NOT auto-synced from git
  to the Proxmox hosts), the actual fix isn't done until it's also
  copied to where it runs. Check each script's own header comment and
  `INSTALL.md` for exactly where that is.

---

# 5. Prompts Worth Using On Yourself

Before writing a Technitium/OPNsense/Proxmox API call:
> "Have I verified this exact endpoint, these exact parameter names, and
> this exact response shape against real source or a live test -- or am
> I pattern-matching from a similar-looking call I saw elsewhere in this
> file?" Similar-looking is not the same as verified; the response
> envelope inconsistency in § 3 is exactly this mistake.

Before running a diagnostic command against a live secret-bearing
endpoint:
> "If this response includes a field I'm not expecting to need, would
> printing it leak a credential? Filter first, print second."

Before telling the user a deploy is ready to retry:
> "Did I check for and clean up leftover temp VMs on every node that
> could hold one?"

Before assuming something is "stuck" or "hanging":
> "Do I have independent evidence this is actually stuck, or am I just
> assuming based on how long it's taken so far?" (Proxmox VM builds can
> legitimately take 20+ minutes.)

Before marking a scaffold/module as done:
> "Did I actually install-and-inspect-and-uninstall against a live
> instance to get the real config shape, or did I write something
> plausible from the name/docs alone?" If the latter, say so explicitly
> in the comment, the way the rest of this repo already does for its
> not-yet-verified scaffolds.
