# VMID Allocation

Ranges:

    <1000   Manual
    3000–3999 Omni
    4000–4999 GitOps

Allocator:

    technitium/terraform/scripts/next-vmid.sh

Flow:

1. Scan Proxmox VMIDs cluster-wide, filtered to the 4000–4999 GitOps range
2. Return the highest VMID found in that range, plus 1 (or 4000 if none exist)

Errors out (does not wrap around) if the range is exhausted at 4999.

Current-production detection:

    technitium/terraform/scripts/current-prod-vmid.sh

Same range filter, but instead of finding the next free ID, it finds
whichever VM in the range currently has `prod_vm_ip` configured. Terraform
uses this to auto-detect the VM to stop/destroy during cutover, so
operators don't need to manually track `old_vm_id` between rebuilds.
Both scripts must be deployed to `/opt/infra/technitium` on every PVE node
(see INSTALL.md) since Terraform invokes them over SSH.
