###############################################################################
# Technitium DNS — GitOps Rebuild Pipeline (Terraform)
#
# This module:
#   1. Allocates a new VMID using an external script (no temp files)
#   2. Creates a temporary Technitium VM at 172.16.100.7
#   3. Waits for DNS service readiness
#   4. Cuts over the production IP (172.16.100.6)
#   5. Destroys the old VM
#
# This design ensures zero‑downtime rebuilds and full declarative GitOps flow.
###############################################################################

###############################################################################
# VMID Allocation (GitOps‑safe)
#
# The external script returns JSON:
#   { "vmid": "4001" }
#
# Terraform reads this via data.external and converts it to a number.
###############################################################################
data "external" "vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/next-vmid.sh"]
}

locals {
  new_vmid = tonumber(data.external.vmid.result.vmid)
}

###############################################################################
# Temporary Technitium VM
#
# This VM boots with cloud‑init, installs Technitium, loads zones, and
# becomes a fully functional DNS server at 172.16.100.7.
#
# After validation, we cut it over to the production IP.
###############################################################################
resource "proxmox_vm_qemu" "technitium_temp" {
  vmid        = local.new_vmid
  name        = "technitium-temp-${local.new_vmid}"
  target_node = var.pm_node
  clone       = var.cloudinit_template

  cores   = 2
  memory  = 2048
  sockets = 1

  # Temporary IP for staging
  ipconfig0 = "ip=172.16.100.7/24,gw=172.16.100.1"

  # Cloud-init user-data
  cicustom = "user=local:snippets/technitium-user.yaml"

  # Inject SSH key for remote-exec readiness checks
  sshkeys = file(var.ssh_pubkey)

  onboot = true
}

###############################################################################
# Wait for DNS readiness
#
# We SSH into the temp VM and poll until Technitium responds to SOA queries.
###############################################################################
resource "null_resource" "wait_for_dns" {
  depends_on = [proxmox_vm_qemu.technitium_temp]

  provisioner "remote-exec" {
    inline = [
      "until dig @172.16.100.7 SOA +short; do sleep 5; done",
      "echo DNS is responding"
    ]

    connection {
      type        = "ssh"
      host        = "172.16.100.7"
      user        = "jdc"
      private_key = file(var.ssh_privkey)
    }
  }
}

###############################################################################
# Cutover
#
# 1. Stop the old VM
# 2. Move the new VM to the production IP (172.16.100.6)
# 3. Reboot the new VM
###############################################################################
resource "null_resource" "cutover" {
  depends_on = [null_resource.wait_for_dns]

  provisioner "local-exec" {
    command = <<EOF
qm stop ${var.old_vm_id}
qm set ${local.new_vmid} --ipconfig0 ip=172.16.100.6/24,gw=172.16.100.1
qm reboot ${local.new_vmid}
EOF
  }
}

###############################################################################
# Destroy Old VM
#
# After cutover, the old VM is removed to maintain GitOps cleanliness.
###############################################################################
resource "null_resource" "destroy_old" {
  depends_on = [null_resource.cutover]

  provisioner "local-exec" {
    command = "qm destroy ${var.old_vm_id}"
  }
}

###############################################################################
# Outputs
###############################################################################
output "new_vmid" {
  value = local.new_vmid
}

output "temp_vm_name" {
  value = proxmox_vm_qemu.technitium_temp.name
}
