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
