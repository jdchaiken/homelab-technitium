# Optional Technitium Apps & Integrations

Reference for every module in [`configure-technitium-apps.yaml`](configure-technitium-apps.yaml).
**Auto PTR, Weighted Round Robin, and Query Logs (PostgreSQL) are enabled**
— wired into `technitium/terraform/main.tf`'s (and `ns2.tf`'s) remote-exec
chain right after `configure-technitium-tls.yaml`, so they run on every
rebuild. The OPNsense TSIG sync was briefly enabled too but is
**disabled again for now** (see its own section below for why) — it needs
a working split-DNS resolution path (ns1 and ns2 both already cut over to
the Conditional Forwarder zone type) to even run, which doesn't exist yet
mid-rebuild, so enabling it created a bootstrapping deadlock on every
deploy that touches either node.
Everything else in the file is still a **commented-out scaffold**. To
enable another module: strip the leading `#` from its lines, fill in the
placeholder values, add any secrets it needs to `bw.env` (see
[`secrets/bw.env.sample`](../../secrets/bw.env.sample)) — it'll then run
automatically on the next rebuild via `main.tf`, or run it by hand
(`ansible-playbook technitium/ansible/configure-technitium-apps.yaml`)
against an already-deployed instance.

Note: this file runs *after* `configure-technitium-tls.yaml`, which moves
the web console off its stock port (5380) to 8443/TLS — `technitium_url` in
this file's `vars:` points at `https://127.0.0.1:8443` accordingly, not the
default.

Everything below except the OPNsense module was verified live against a
running Technitium 15.3 instance — installed for real, config pulled from
the live API, then uninstalled. See each section for exactly what that
means for that module, and for the one module that couldn't be verified
this way.

---

## Auto PTR — **live**

Generates PTR records automatically for A/AAAA records in primary/forwarder
zones.

- **Secrets needed:** none.
- **Config:** none — confirmed live that this app has no config file at all
  (`GET config` returns `#This app requires no config.`).

## Weighted Round Robin — **live**

APP records that distribute answers across multiple IPs by weight.

- **Secrets needed:** none.
- **Config:** none — same as Auto PTR, confirmed live.

## Advanced Blocking

Per-client/per-network blocking groups, each with its own allow/block lists
and regex lists.

- **Secrets needed:** none — block list URLs are public.
- **Config:** the scaffold's example trims the verified default shape down
  to a single "everyone" group covering `0.0.0.0/0`/`::/0`. Replace with
  your own `networkGroupMap` and `groups` as needed.

## Failover

Health-checked APP records with optional email/webhook alerting when a
target goes down.

- **Secrets needed:** `TECHNITIUM_FAILOVER_SMTP_PASSWORD` (only if you
  enable email alerts).
- **Config:** health checks (ping/tcp/http/https), email alert profiles,
  webhook profiles, and per-network maintenance windows. Alerts are
  disabled by default in the example; flip `enabled` once
  `smtpServer`/`alertTo`/webhook `urls` are filled in for real.

## Log Exporter

Ships query logs to file, HTTP, or syslog sinks.

- **Secrets needed:** `TECHNITIUM_LOGEXPORTER_HTTP_TOKEN` (only if you
  enable the HTTP sink).
- **Config:** all three sinks (file/HTTP/syslog) are disabled by default in
  the example; enable the ones you want and fill in the real endpoint/path.

## Query Logs (PostgreSQL)

Replaces Technitium's default query log storage with PostgreSQL.

- **Secrets needed:** `TECHNITIUM_QUERYLOGS_PG_CONFIG` — a single JSON
  secret (`server`, `username`, `password`, `port`, `databaseName`) instead
  of separate keys, same reasoning as
  `TECHNITIUM_SSO_CONFIG`/`OPNSENSE_API_CONFIG` — the whole connection
  config stays out of this file and out of bw.env as loose fragments, not
  just the password.
- **Config:** nothing left to set directly in the scaffold — the entire
  connection (including `databaseName`) comes from the JSON secret above.

## SSO (OpenID Connect)

Configures Technitium's Administration > SSO login — a core feature, not a
DNS App, so there's no install step, just one `settings/set`-equivalent
call to `/api/admin/sso/set`. Works with any standard OIDC provider
(Authentik, Okta, Entra ID, Keycloak, ...).

- **Secrets needed:** `TECHNITIUM_SSO_CONFIG` — a single JSON secret
  (authority, client ID, client secret, group map) instead of four separate
  keys, to keep this to one secret lookup.
- **Verified live:** the endpoint and response shape, via the read-only Get
  SSO Config call.
- **Not independently verified:** `ssoGroupMap`'s exact pipe-delimited
  format. It follows the same flat
  `row1key|row1value|row2key|row2value` convention already confirmed for
  `tsigKeys` in `configure-technitium.yaml`, but wasn't write-tested for
  SSO specifically — double check against the web console
  (Administration > SSO) before relying on it.

## OPNsense TSIG Sync — disabled again (bootstrapping deadlock)

Was briefly enabled and live-tested (2026-07-16). It correctly resolves
`OPNSENSE_API_CONFIG`'s `host` (confirmed the scheme/hostname needs to be
`https://opnsense.example.com`, not a bare IP -- there's a reverse proxy
doing SNI-based routing in front of OPNsense) and correctly authenticates
-- but resolving that hostname from *inside* the Technitium VM depends on
split-DNS conditional forwarding already working, which in turn depends
on ns1 and ns2 both already being fully cut over to the Conditional
Forwarder zone type. During any deploy that rebuilds either node, this
task runs mid-build, before that's true -- it ends up asking whichever
node (old or new) is currently answering for the zone, and if that's the
pre-cutover instance, resolution fails outright (`NXDOMAIN`) or, before
the `dnssecValidation: false` fix, hangs on a spurious DNSSEC failure
(`SERVFAIL`). Re-enable this once ns1/ns2 have both been running the
Conditional Forwarder code for a while and split-DNS is confirmed stable
-- at that point the bootstrapping problem doesn't apply anymore, since
the resolver this task depends on will already be up before the rebuild
that re-triggers this task even starts.

Not a Technitium feature — configures **OPNsense's** Kea DHCP DDNS settings
so DHCP leases get registered into Technitium via authenticated RFC2136
dynamic updates. Reuses the TSIG key `configure-technitium.yaml` already
generated (fetched from Bitwarden **by name**, not regenerated — a
hardcoded secret ID would go stale the next time the key rotates, since
`bws secret create` isn't idempotent and issues a new ID every time).

- **Secrets needed:** `OPNSENSE_API_CONFIG` — a single JSON secret (host,
  API key, API secret). Generate the key/secret pair under OPNsense's own
  System > Access > Users > (user) > API Keys page.
- **What it does:** lists every configured Kea DHCPv4 and DHCPv6 subnet,
  pushes the TSIG key + forward zone + Technitium's IP onto each one's
  `ddns_*` fields, then triggers `service/reconfigure` to apply.
- **Verified, but not live:** the field names (`ddns_forward_zone`,
  `ddns_dns_server`, `ddns_dns_port`, `ddns_domain_key_name`,
  `ddns_domain_key_secret`, `ddns_domain_key_algorithm`) and API endpoints
  (`/api/kea/dhcpv{4,6}/search_subnet`, `/api/kea/dhcpv{4,6}/set_subnet/<uuid>`,
  `/api/kea/service/reconfigure`) come directly from OPNsense's own source
  on GitHub (`opnsense/core`), not documentation or guesswork — but no
  OPNsense instance was available to actually run this against. Three
  specific things to confirm on first real use (see the in-file comment
  for the full reasoning):
  1. Whether `set_subnet` truly accepts a partial body (only the `ddns_*`
     fields) without clobbering the rest of that subnet's config.
  2. Whether `search_subnet`'s response really has the standard OPNsense
     shape (`{"rows": [{"uuid": ..., ...}]}`).
  3. Whether Technitium and Kea actually agree on the TSIG secret's raw
     bytes — both should treat it as base64 per RFC 2845 (Technitium's
     generated secret is valid unpadded base64 by construction: exactly
     32 characters, a multiple of 4, drawn from a subset of the base64
     alphabet), but this hasn't been confirmed with an actual signed
     update.
  4. Kea's TSIG/DDNS support in OPNsense is relatively recent history —
     if your OPNsense version predates it, none of this exists in the API
     at all.

The Ansible task block itself is uncommented and will run on the next
rebuild as soon as `OPNSENSE_API_CONFIG` is set in `bw.env` with real
values — but the four points above are still only verified against
OPNsense's own source, not against a live run. Watch the first real deploy
closely (or run this playbook by hand against a non-prod OPNsense first,
if one's available) before trusting it against production DHCP subnets.
