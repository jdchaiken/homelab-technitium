# VM Lifecycle Flow

1. Terraform allocates a VMID
2. Terraform creates the temporary VM from the cloud-init template
3. Terraform waits for cloud-init to finish — cloud-init clones this
   repo onto the VM and runs the install + configure Ansible playbooks
   locally, which install Technitium, bootstrap its admin account,
   create an API key, generate a TSIG key, and import DNS zones
4. Terraform polls DNS on the temporary IP until Technitium answers
5. Terraform stops the old VM, moves the new VM to the production IP,
   and reboots it
6. Terraform destroys the old VM
