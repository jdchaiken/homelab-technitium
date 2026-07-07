# GitOps DNS Architecture (Mermaid)

```mermaid
flowchart LR
    subgraph G[Git Repository]
        G1[Zones]
        G2[Scripts]
        G3[Terraform]
        G4[Ansible]
    end

    subgraph CI[Gitea CI/CD]
        CI1[Syntax Validation]
        CI2[Strict Diff Checker]
        CI3[Serial Enforcement]
        CI4[Secret Scanning]
    end

    subgraph TF[Terraform]
        TF1[VMID Allocation]
        TF2[VM Creation]
        TF3[DNS Readiness Check]
        TF4[Zero-Downtime Cutover]
    end

    subgraph PX[Proxmox]
        PX1[Cloud-init Template]
        PX2[VM Lifecycle]
        PX3[Bitwarden Env Storage]
    end

    subgraph CI2A[Cloud-init]
        CI2A1[Clone Repo]
        CI2A2[Load Bitwarden Env]
        CI2A3[Run Ansible]
    end

    subgraph AN[Ansible]
        AN1[Install Technitium]
        AN2[Configure TSIG]
        AN3[Import Zones]
        AN4[Configure RFC2136]
    end

    subgraph DNS[Technitium DNS]
        DNS1[Authoritative DNS Server]
    end

    G --> CI
    CI --> TF
    TF --> PX
    PX --> CI2A
    CI2A --> AN
    AN --> DNS
