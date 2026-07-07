# Secrets Flow

Bitwarden → Proxmox → Cloud-init → Ansible → Technitium

Bitwarden:
    TSIG Name
    TSIG Algorithm
    TSIG Secret

Proxmox:
    bw.env

Cloud-init:
    Copies bw.env

Ansible:
    Fetches secrets

Technitium:
    Configured with TSIG
