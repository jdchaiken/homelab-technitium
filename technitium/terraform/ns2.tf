###############################################################################
# ns2 -- Secondary DNS Server
#
# Mirrors main.tf's technitium_temp / wait_for_dns / cutover pattern for a
# second, independent Technitium instance living alongside ns1 in the same
# workspace (not a swapped-in replacement like staging's workspace-based
# approach -- ns2 co-exists with ns1, it doesn't replace it). Kept as an
# explicit, separate resource set rather than a shared module: the two
# roles differ enough in what they configure (Secondary zones + zone
# transfer vs Primary zones + zone-file import) that a forced abstraction
# right now would cost more than it saves. Worth revisiting once patterns
# stabilize across both.
###############################################################################

data "external" "ns2_vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/next-vmid.sh"]
}

data "external" "ns2_current_prod_vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/current-prod-vmid.sh"]
  query = {
    prod_ip = trimspace(element(split("/", var.ns2_prod_vm_ip), 0))
  }
}

locals {
  ns2_new_vmid   = tonumber(data.external.ns2_vmid.result.vmid)
  ns2_bw_env_tmp = "/tmp/technitium-ns2-bw-env-${local.ns2_new_vmid}"

  ns2_detected_old_vm_id = data.external.ns2_current_prod_vmid.result.vmid != "" ? tonumber(data.external.ns2_current_prod_vmid.result.vmid) : null
  ns2_old_vm_id          = var.ns2_old_vm_id != null ? var.ns2_old_vm_id : local.ns2_detected_old_vm_id
}

resource "terraform_data" "ns2_rebuild_trigger" {
  input = var.ns2_rebuild_id
}

resource "proxmox_virtual_environment_vm" "technitium_ns2_temp" {
  name      = "technitium-ns2-temp"
  node_name = var.ns2_target_node
  vm_id     = local.ns2_new_vmid

  lifecycle {
    replace_triggered_by  = [terraform_data.ns2_rebuild_trigger]
    create_before_destroy = true
    ignore_changes = [
      vm_id,
      initialization,
      name,
    ]
  }

  clone {
    # node_name here is the SOURCE node (where template 9000 actually
    # lives) -- required whenever it differs from this resource's own
    # node_name (the target). Confirmed via the provider's own schema
    # (terraform providers schema -json): clone.node_name is documented as
    # "The name of the source node". Without it, Proxmox returns "unable to
    # find configuration file for VM 9000 on node 'pve04'", since the
    # template is only registered under target_node's node (pve02).
    node_name = var.target_node
    vm_id     = var.cloudinit_template
    full      = false
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = "itank"
    interface    = "scsi0"
    size         = 8
  }

  network_device {
    bridge = "Servers"
    model  = "virtio"
  }

  initialization {
    datastore_id = "tank"

    user_data_file_id = "tank:snippets/technitium-user-ns2.yaml"

    user_account {
      username = "root"
      password = var.vm_password
    }

    ip_config {
      ipv4 {
        address = var.ns2_temp_vm_ip
        gateway = var.gateway_ip
      }
    }
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = trimspace(element(split("/", var.ns2_temp_vm_ip), 0))
    private_key = file(var.ssh_privkey)
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  # Delivered from the SAME /etc/pve/technitium/bw.env as ns1 -- shared
  # cluster-wide via the Proxmox host, not per-instance. This is exactly
  # what lets configure-technitium-secondary.yaml fetch ns1's real TSIG key
  # from Bitwarden by name.
  provisioner "local-exec" {
    command = "ssh root@${var.pm_node} cat /etc/pve/technitium/bw.env > ${local.ns2_bw_env_tmp} && chmod 600 ${local.ns2_bw_env_tmp}"
  }

  provisioner "file" {
    source      = local.ns2_bw_env_tmp
    destination = "/root/bw.env"
  }

  provisioner "local-exec" {
    command = "rm -f ${local.ns2_bw_env_tmp}"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod 600 /root/bw.env",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/install-technitium.yaml",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium-secondary.yaml -e dns_hostname=${var.ns2_dns_hostname}",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium-tls.yaml -e dns_hostname=${var.ns2_dns_hostname} -e nfs_subdir=${var.ns2_nfs_subdir}",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium-apps.yaml -e dns_hostname=${var.ns2_dns_hostname}",
    ]
  }
}

resource "null_resource" "ns2_wait_for_dns" {
  triggers = {
    vm_instance_id = proxmox_virtual_environment_vm.technitium_ns2_temp.id
  }

  depends_on = [proxmox_virtual_environment_vm.technitium_ns2_temp]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      VM_IP="$(echo "${var.ns2_temp_vm_ip}" | cut -d'/' -f1)"
      HOSTNAME="${var.ns2_dns_hostname}"

      echo "Waiting for DNS on $VM_IP..."

      for i in $(seq 1 360); do
        if dig +short @$VM_IP $HOSTNAME SOA >/dev/null 2>&1; then
          echo "DNS is ready on $VM_IP"
          exit 0
        fi
        sleep 5
      done

      echo "DNS did not become ready in time"
      exit 1
    EOT
  }
}

resource "null_resource" "ns2_cutover" {
  triggers = {
    vm_instance_id = proxmox_virtual_environment_vm.technitium_ns2_temp.id
  }

  depends_on = [null_resource.ns2_wait_for_dns]

  # Unlike ns1's cutover, these qm commands SSH to ns2_target_node, not
  # pm_node -- ns2 lives on a different physical node than pm_node (pve02),
  # and qm start/stop/set/reboot are state-changing commands that must run
  # on the node actually hosting the VM (unlike qm config, which reads
  # pmxcfs's cluster-wide shared config and works from any node -- that's
  # why VMID allocation/detection above stay on pm_node).
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      %{if local.ns2_old_vm_id != null~}
      echo "Stopping old ns2 VM ${local.ns2_old_vm_id}..."
      ssh root@${var.ns2_target_node} "qm stop ${local.ns2_old_vm_id}"
      %{else~}
      echo "No previous ns2 VM detected -- nothing to stop (first build or post-destroy rebuild)."
      %{endif~}

      PROD_IP="$(echo "${var.ns2_prod_vm_ip}" | cut -d'/' -f1)"
      CIDR="$(echo "${var.ns2_prod_vm_ip}" | cut -d'/' -f2)"

      echo "Setting new ns2 VM ${local.ns2_new_vmid} to production IP $PROD_IP/$CIDR..."
      ssh root@${var.ns2_target_node} "qm set ${local.ns2_new_vmid} --ipconfig0 ip=$PROD_IP/$CIDR,gw=${var.gateway_ip}"

      echo "Renaming new ns2 VM ${local.ns2_new_vmid} to ${var.ns2_prod_vm_name}..."
      ssh root@${var.ns2_target_node} "qm set ${local.ns2_new_vmid} --name ${var.ns2_prod_vm_name}"

      echo "Rebooting new ns2 VM ${local.ns2_new_vmid}..."
      ssh root@${var.ns2_target_node} "qm reboot ${local.ns2_new_vmid}"
    EOT
  }
}
