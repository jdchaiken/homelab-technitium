# Infrastructure Overview

    ┌──────────────┐
    │   Proxmox     │
    │  VM Template  │
    └──────┬────────┘
           │
           ▼
    ┌──────────────┐
    │  Cloud-init   │
    │  technitium   │
    └──────┬────────┘
           │
           ▼
    ┌──────────────┐
    │   Ansible     │
    │ Install/Config│
    └──────┬────────┘
           │
           ▼
    ┌──────────────┐
    │ Technitium    │
    │ Authoritative │
    └──────────────┘
