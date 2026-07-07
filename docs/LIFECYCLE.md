# VM Lifecycle Flow

1. Terraform allocates VMID
2. Terraform creates temporary VM
3. Cloud-init configures VM
4. Ansible installs Technitium
5. DNS validated
6. Old VM stopped
7. IP swapped
8. Old VM destroyed
