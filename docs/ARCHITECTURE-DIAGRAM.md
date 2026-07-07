# GitOps DNS Architecture (ASCII Diagram)

                     ┌──────────────────────────┐
                     │        Git Repo           │
                     │  dns/ zones/ scripts/     │
                     │  technitium/ terraform/   │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │        Gitea CI/CD        │
                     │  - Syntax validation      │
                     │  - Strict diff checker    │
                     │  - Serial enforcement     │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │        Terraform          │
                     │  - VMID allocation        │
                     │  - VM creation            │
                     │  - DNS readiness check    │
                     │  - Zero-downtime cutover  │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │         Proxmox           │
                     │  - Cloud-init template    │
                     │  - VM lifecycle           │
                     │  - Bitwarden env storage  │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │        Cloud-init         │
                     │  - Clone repo             │
                     │  - Load Bitwarden env     │
                     │  - Run Ansible            │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │         Ansible           │
                     │  - Install Technitium     │
                     │  - Configure TSIG         │
                     │  - Import zones           │
                     │  - Configure RFC2136      │
                     └─────────────┬────────────┘
                                   │
                                   ▼
                     ┌──────────────────────────┐
                     │     Technitium DNS        │
                     │  Authoritative DNS Server │
                     └──────────────────────────┘
