flowchart TD
    A[Git Repo] --> B[Gitea CI/CD]
    B --> C[Terraform]
    C --> D[Proxmox]
    D --> E[Cloud-init]
    E --> F[Ansible]
    F --> G[Technitium DNS]

    subgraph Git Repo
        zones[Zones]
        scripts[Scripts]
        terraform[Terraform Module]
        ansible[Ansible Playbooks]
    end

    subgraph CI/CD
        syntax[Syntax Validation]
        strict[Strict Diff Checker]
        serial[Serial Enforcement]
    end

    subgraph Terraform
        vmid[VMID Allocation]
        vmcreate[VM Creation]
        dnscheck[DNS Readiness]
        cutover[Zero-Downtime Cutover]
    end

    subgraph Proxmox
        template[Cloud-init Template]
        lifecycle[VM Lifecycle]
        bwenv[Bitwarden Env Storage]
    end

    subgraph Cloud-init
        clone[Clone Repo]
        loadenv[Load Bitwarden Env]
        runansible[Run Ansible]
    end

    subgraph Ansible
        install[Install Technitium]
        config[Configure TSIG]
        zonesimport[Import Zones]
        rfc2136[Configure RFC2136]
    end
