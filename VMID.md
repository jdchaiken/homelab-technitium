# VMID Allocation

Ranges:

    <1000   Manual
    3000–3999 Omni
    4000–4999 GitOps

Allocator:

    technitium/terraform/scripts/next-vmid.sh

Flow:

1. Scan all Proxmox VMIDs cluster-wide (`pvesh get /cluster/resources --type vm`)
2. Return the highest VMID found, plus 1 (or 4000 if the cluster has no VMs)

Known gap: the allocator does not filter to the 4000–4999 GitOps range
and has no wraparound — it will keep incrementing past 4999 if higher
VMIDs exist elsewhere in the cluster. Keep VMIDs above 4999 out of use
until this is tightened.
