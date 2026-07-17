# TODO / Future Work

Proposed, scoped, but not started. Each item below was investigated
against the real codebase (not guessed) before estimating -- see each
item's "Investigation" section for what was actually traced through the
repo.

---

# 1. Pluggable Secrets Manager Backend

**Goal:** let a different deployment of this project use HashiCorp Vault
or AWS Secrets Manager instead of Bitwarden Secrets Manager, without a
rewrite -- configurable, not hardcoded.

**Status:** estimated 2026-07-17, not started.

## Investigation

Traced every `bws` CLI call site in the repo before estimating, rather
than assuming the coupling is as broad as "uses Bitwarden" suggests.
Findings:

- **Most secrets never touch the Bitwarden API at all.** `bw.env` is a
  bootstrap file -- `TECHNITIUM_ADMIN_PASSWORD`, `CLOUDFLARE_API_TOKEN`,
  `ACME_EMAIL`, `TECHNITIUM_QUERYLOGS_PG_CONFIG`, `TECHNITIUM_SSO_CONFIG`,
  `OPNSENSE_API_CONFIG` all live there directly as plaintext, by design,
  and are never fetched from Bitwarden. This is a deliberate distinction
  already documented in this repo: bw.env holds credentials directly;
  only the TSIG key round-trips through Bitwarden.

- **Only two logical secrets actually round-trip through the Bitwarden
  API:**
  1. The generated TSIG key (name/algorithm/secret) -- **written** by
     `configure-technitium.yaml` after every ns1 rebuild, **read back**
     by staging (reuses prod's key by name) and by the OPNsense sync
     module (`configure-technitium-apps.yaml`).
  2. The Technitium Ansible API key -- **written** only, never read back.

- **Actual `bws` CLI call sites** (four, across three files):
  - `technitium/ansible/configure-technitium.yaml` -- the
    `upsert_secret()` bash function (create-or-update via
    `bws secret list` + `edit`/`create`/`delete`), used twice (API key,
    TSIG key); plus one `bws secret list` fetch for the staging path.
  - `technitium/ansible/configure-technitium-apps.yaml` -- one
    `bws secret list` fetch (OPNsense TSIG sync module).
  - `technitium/ansible/install-technitium.yaml` -- installs the `bws`
    CLI binary itself, unconditionally, on every VM. Noticed while
    tracing this: ns2 installs it but never actually calls it (ns2's own
    playbook never touches TSIG at all -- relies on an IP-based zone
    transfer ACL instead). Not a blocker for this item, just an existing
    minor inefficiency worth cleaning up either way.

- **The Kubernetes side (External Secrets Operator) is effectively
  free.** The `ClusterSecretStore`/`ExternalSecret` layer already
  natively supports Vault, AWS Secrets Manager, and Bitwarden as
  interchangeable providers -- swapping that is a different
  `ClusterSecretStore` manifest in the cluster's own repo, not a code
  change here.

## Proposed Approach

Define a minimal common interface -- `get_secret <name>` /
`upsert_secret <name> <value>` -- and refactor the existing Bitwarden
logic (the `upsert_secret()` function and the `bws secret list` fetches)
behind it, selected via a new variable (e.g. `secrets_backend:
bitwarden|vault|aws`) set in tfvars/group_vars.

## Effort Breakdown

- **Interface + Bitwarden-backend refactor:** low risk, mostly moving
  code that already works into a named backend implementation.
- **Second backend, implemented for real:** this is where the actual
  time goes. This project's standing discipline has been to verify
  every API call against real source or a live instance, never guess
  syntax from docs alone (see git history -- this has caught real bugs
  every single time it was skipped). Holding a new backend to the same
  bar means testing against an actual live Vault or AWS Secrets Manager
  instance, not just writing plausible-looking code.
  - **Vault** is the more natural first choice -- closer to Bitwarden's
    CLI-driven, token-authenticated model.
  - **AWS Secrets Manager** has an open design question that needs a
    real decision, not just implementation: Proxmox VMs aren't EC2
    instances, so there's no IAM instance-role shortcut for
    authentication -- likely static AWS access keys living in bw.env,
    which is a real security tradeoff worth its own conversation before
    committing to it.
- **`install-technitium.yaml`:** needs to install whichever CLI the
  selected backend requires, conditionally (or skip entirely for a
  backend that's REST-only with no CLI dependency).
- **`bw.env`'s bootstrap shape is inherently backend-specific:**
  Bitwarden needs `BW_TOKEN`/`BW_ORGID`/`BW_PROJECTID`; Vault needs an
  address + token/AppRole; AWS Secrets Manager needs whatever
  credentials get chosen above. `secrets/bw.env.sample` and the "Read
  Bitwarden environment file" tasks become backend-aware.
- **Docs:** `SECRETS-FLOW.md`, `bw.env.sample`, `INSTALL.md`,
  `ARCHITECTURE.md` all reference Bitwarden by name today and need
  updating to describe the pluggable model.

**Overall: medium lift, not small, not a rewrite.** The code surface is
genuinely narrow (four call sites, two secrets), so the mechanical
refactor is quick. The real cost is testing a second backend to the same
live-verified standard the rest of this project holds -- that's
expected to take more time than the abstraction work itself.

---

# 2. Scaffold Every Technitium DNS App in configure-technitium-apps.yaml

**Goal:** every DNS App Technitium's store actually offers gets a
scaffold entry in `configure-technitium-apps.yaml` -- commented out by
default like the existing ones, but with real, live-verified install
endpoints and config field names ready to uncomment, not placeholders to
fill in later.

**Status:** proposed 2026-07-17, not started.

## Investigation

Pulled the real, current app catalog from a live instance
(`GET /api/apps/listStoreApps`) rather than assuming the existing
scaffolds already cover what's available -- 27 apps exist today. Only 6
have any scaffold in the file:

| Already scaffolded | State |
| --- | --- |
| Auto PTR | live/enabled |
| Weighted Round Robin | live/enabled |
| Query Logs (PostgreSQL) | live/enabled |
| Advanced Blocking | commented scaffold |
| Failover | commented scaffold |
| Log Exporter | commented scaffold |

**21 apps have no scaffold at all:** Advanced Forwarding, Block Page,
Default Records, DNS64, DNS Block List (DNSBL), DNS Rebinding
Protection, Drop Requests, Filter AAAA, Geo Continent, Geo Country, Geo
Distance, NO DATA, NX Domain, NX Domain Override, Query Logs (MySQL),
Query Logs (Sqlite), Query Logs (SQL Server), Split Horizon, What Is My
Dns, Wild IP, Zone Alias.

## Approach

Same recipe already used for every existing scaffold in the file, not a
new pattern -- per this project's standing rule, don't guess a config
shape from an app's name:

1. Install the app for real against a test instance
   (`/api/apps/downloadAndInstall`).
2. `GET /api/apps/config/get` to capture its actual default config (some
   apps, like Auto PTR/Weighted Round Robin, turn out to need no config
   at all -- confirmed live, not assumed; several of the 21 above look
   like likely candidates for the same, e.g. Drop Requests, Filter
   AAAA, NX Domain, NO DATA -- but that needs confirming per app, not
   guessing from the name).
3. Uninstall, write the scaffold task (install + config, matching the
   existing file's structure/comments), commented out by default.

## Effort

Mechanical and well-understood (the pattern already exists 6 times over
in this file) but not small purely by volume: 21 apps, each needing its
own live install/inspect/uninstall cycle before the scaffold can be
trusted. The three additional Query Logs backends (MySQL, Sqlite, SQL
Server) are likely the fastest of the batch -- probably close siblings
of the already-verified PostgreSQL one, but still worth confirming
rather than assuming their config field names match exactly.
