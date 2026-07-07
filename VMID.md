# VMID Allocation

Ranges:

    <1000   Manual
    3000–3999 Omni
    4000–4999 GitOps

Allocator:

    next-vmid.sh

Flow:

1. Scan Proxmox VMIDs
2. Find next free in 4000–4999
3. Wrap to 4000 if needed
