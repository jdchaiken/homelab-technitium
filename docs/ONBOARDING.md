# Onboarding Guide – GitOps DNS Platform

Welcome to the GitOps DNS platform. This guide will get you fully onboarded.

---

# 1. Prerequisites

You need:

- Access to the Git repo
- Access to Proxmox
- Access to Bitwarden Secrets Manager
- SSH keys for Terraform/Ansible
- Gitea account

---

# 2. Clone the Repo

    git clone <repo-url>
    cd <repo>

---

# 3. Understand the Structure

    dns/            # DNS zones + validation
    technitium/     # Ansible, cloud-init, Terraform
    secrets/        # Bitwarden env templates

---

# 4. Configure Secrets

Copy:

    secrets/bw.env.sample

Into Proxmox:

    /etc/pve/technitium/bw.env

Set:

- BW_TOKEN
- BW_ORGID
- BW_PROJECTID

---

# 5. Configure Terraform

Edit:

    technitium/terraform/terraform.tfvars

Set:

- pm_api_url
- pm_user
- pm_password
- pm_node
- cloudinit_template
- ssh_pubkey
- ssh_privkey
- old_vm_id

---

# 6. Validate DNS

    make validate-zones

---

# 7. Deploy

    make deploy

This performs a zero-downtime rebuild.

---

# 8. Validate DNS After Deployment

    dig @172.16.100.6 SOA
    dig @172.16.100.6 <hostname> A

---

# 9. Summary

You are now fully onboarded.
