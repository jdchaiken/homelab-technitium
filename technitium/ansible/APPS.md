# Optional Technitium Apps & Integrations

Reference for every module in [`configure-technitium-apps.yaml`](configure-technitium-apps.yaml).
**Auto PTR, Weighted Round Robin, Query Logs (PostgreSQL), and the OPNsense
TSIG sync are enabled** — wired into `technitium/terraform/main.tf`'s (and
`ns2.tf`'s) remote-exec chain right after `configure-technitium-tls.yaml`,
so they run on every rebuild. OPNsense was previously disabled for a
bootstrapping deadlock (it depends on split-DNS resolution, which mid-
rebuild doesn't exist yet on a node that isn't cut over) -- safe to
re-enable now that ns1 and ns2 are both stable on the Conditional Forwarder
zone type before any new rebuild starts. See its own section below for
what it actually does and two related settings it doesn't cover.
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

## OPNsense TSIG Sync — enabled, live-verified end-to-end

Not a Technitium feature — configures **OPNsense's** Kea DHCP DDNS settings
so DHCP leases get registered into Technitium via authenticated RFC2136
dynamic updates. Reuses the TSIG key `configure-technitium.yaml` already
generated (fetched from Bitwarden **by name**, not regenerated — a
hardcoded secret ID would go stale the next time the key rotates, since
`bws secret create` isn't idempotent and issues a new ID every time).

- **Secrets needed:** `OPNSENSE_API_CONFIG` — a single JSON secret (host,
  API key, API secret). Generate the key/secret pair under OPNsense's own
  System > Access > Users > (user) > API Keys page. `host` needs a scheme
  and the real hostname, not a bare IP — `https://opnsense.example.com`,
  confirmed live: if OPNsense sits behind a reverse proxy doing SNI-based
  routing (Caddy, in this setup), connecting by IP fails the TLS handshake
  entirely since the proxy can't pick the right backend without SNI.
- **What it does:** lists every configured Kea DHCPv4 and DHCPv6 subnet,
  pushes the TSIG key + forward zone + qualifying suffix + Technitium's IP
  onto each one's `ddns_*` fields, then triggers `service/reconfigure` to
  apply.
- **Live-tested end-to-end (2026-07-17)**, all the way through a real DHCP
  lease renewal producing a signed DDNS update Technitium accepted and
  wrote to the zone. Confirmed along the way: `set_subnet`'s partial-body
  update only touches the fields sent (verified against
  `ApiMutableModelControllerBase::setBase()`'s `setNodes()`, not just
  observed behavior); `search_subnet`'s response shape is exactly
  `{"rows": [...]}`; Technitium's plain-alphanumeric secret and Kea's
  base64 `ddns_domain_key_secret` field decode identically (a real signed
  update succeeded).
- **Two related settings this module does NOT cover**, both required for
  DDNS to actually work, found by walking a real failure end to end:
  1. Kea's DHCP-DDNS (D2) daemon's own `server_ip` general setting (OPNsense:
     Services > Kea DHCP > DHCP DDNS) must be `127.0.0.1` — its own local
     listen address, where `kea-dhcp4` hands it internal
     NameChangeRequests. This is easy to mix up with the per-subnet
     `ddns_dns_server` field (the *actual* DNS server, correctly
     `172.16.100.6`) since they sit right next to each other in the UI —
     but they're two different hops in the pipeline (`kea-dhcp4` → D2 →
     Technitium), and D2 can't bind to a remote IP it doesn't own. This is
     a one-time OPNsense-side setting, not something this Ansible module
     manages.
  2. Technitium's `updateSecurityPolicies` (`configure-technitium.yaml`)
     must include `DHCID` in the allowed record types, alongside
     `A,AAAA,CNAME,TXT,SRV`. Kea's `check-with-dhcid` conflict-resolution
     mode (OPNsense's default) sends a DHCID record in the same atomic
     UPDATE transaction as the A/AAAA record — Technitium refuses the
     *entire* transaction if any record type in it isn't permitted, even
     though the A record alone would have been fine. Confirmed directly
     from Technitium's own log: `DNS Server refused a zone UPDATE request
     [host.example.com DHCID IN] due to Dynamic Updates Security Policy`.
- Kea's TSIG/DDNS support in OPNsense is relatively recent history — if
  your OPNsense version predates it, none of this exists in the API at
  all.
