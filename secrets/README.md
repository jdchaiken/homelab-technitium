# Secrets Management

This directory contains templates and documentation for secret handling.

Real secrets are never stored in Git.

---

## Bitwarden Secrets Manager

TSIG keys and API credentials are stored in Bitwarden.

Required secrets:

- externaldns-tsig-name
- externaldns-tsig-algorithm
- externaldns-tsig-secret

Each secret has a Bitwarden Secret ID.

Ansible retrieves secrets using these IDs.

---

## Proxmox Secret Storage

Proxmox stores Bitwarden credentials at:

    /etc/pve/technitium/bw.env

Contents:

    BW_TOKEN="your-bitwarden-service-account-token"
    BW_ORGID="your-organization-id"
    BW_PROJECTID="your-project-id"

Permissions:

    chmod 600 /etc/pve/technitium/bw.env

Cloud-init copies this file into the VM.

---

## Files in This Directory

### bw.env.sample
Template for Bitwarden credentials.

### .gitignore
Ensures real secrets are never committed.

---

## Summary

This directory contains:

- Bitwarden secret templates
- Documentation for secret handling
- Gitignore protections

Secrets are always external.
Never stored in Git.
