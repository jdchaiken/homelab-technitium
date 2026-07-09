###############################################################################
# Terraform + Providers
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.111"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.pm_api_url
  username = var.pm_user
  password = var.pm_password
  insecure = true
}

provider "external" {}
provider "null" {}

###############################################################################
# VMID Allocation (GitOps-safe)
###############################################################################

data "external" "vmid" {
  program = ["ssh", "root@${var.pm_node}", "/opt/infra/technitium/next-vmid.sh"]
}

locals {
  new_vmid   = tonumber(data.external.vmid.result.vmid)
  bw_env_tmp = "/tmp/technitium-bw-env-${local.new_vmid}"
}

###############################################################################
# Temporary Technitium VM (Cloud-init)
###############################################################################

resource "proxmox_virtual_environment_vm" "technitium_temp" {
  name      = "technitium-temp"
  node_name = var.target_node
  vm_id     = local.new_vmid

  # Clone Debian cloud-init template
  clone {
    vm_id = var.cloudinit_template
    full  = false
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

  # Resize/move cloned disk to iSCSI storage "itank"
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

    user_data_file_id = "tank:snippets/technitium-user.yaml"

    user_account {
      username = "root"
      password = var.vm_password
    }

    ip_config {
      ipv4 {
        address = var.temp_vm_ip
        gateway = var.gateway_ip
      }
    }
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = trimspace(element(split("/", var.temp_vm_ip), 0))
    private_key = file(var.ssh_privkey)
  }

  # Wait for cloud-init (package installs, repo clone) to finish before
  # touching the VM further.
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  # Deliver the Bitwarden env file from the Proxmox host into the guest.
  # qemu-guest-agent cannot do this: it lets the host read/write files in
  # the guest, not the other way around, so a guest-side "file-read" of a
  # host path silently fails. Terraform itself does not run on pve01 either,
  # so relay the file through a local scratch copy (never stored in state,
  # unlike a data source would be) fetched over SSH and deleted right after
  # use.
  provisioner "local-exec" {
    command = "ssh root@${var.pm_node} cat /etc/pve/technitium/bw.env > ${local.bw_env_tmp} && chmod 600 ${local.bw_env_tmp}"
  }

  provisioner "file" {
    source      = local.bw_env_tmp
    destination = "/root/bw.env"
  }

  provisioner "local-exec" {
    command = "rm -f ${local.bw_env_tmp}"
  }

  # Run the Ansible playbooks only now that bw.env is actually present.
  # (These used to run from cloud-init's runcmd, which starts them before
  # Terraform has a chance to deliver bw.env.)
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /root/bw.env",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/install-technitium.yaml",
      "ansible-playbook /opt/infra/technitium/technitium/ansible/configure-technitium.yaml",
    ]
  }
}

###############################################################################
# Wait for DNS Readiness (Technitium authoritative check)
###############################################################################

resource "null_resource" "wait_for_dns" {
  depends_on = [proxmox_virtual_environment_vm.technitium_temp]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      VM_IP="$(echo "${var.temp_vm_ip}" | cut -d'/' -f1)"
      HOSTNAME="technitium.example.com"

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

###############################################################################
# Cutover: Move New VM to Production IP
###############################################################################

resource "null_resource" "cutover" {
  depends_on = [null_resource.wait_for_dns]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Stopping old VM ${var.old_vm_id}..."
      ssh root@${var.pm_node} "qm stop ${var.old_vm_id}"

      PROD_IP="$(echo "${var.prod_vm_ip}" | cut -d'/' -f1)"
      CIDR="$(echo "${var.prod_vm_ip}" | cut -d'/' -f2)"

      echo "Setting new VM ${local.new_vmid} to production IP $PROD_IP/$CIDR..."
      ssh root@${var.pm_node} "qm set ${local.new_vmid} --ipconfig0 ip=$PROD_IP/$CIDR,gw=${var.gateway_ip}"

      echo "Rebooting new VM ${local.new_vmid}..."
      ssh root@${var.pm_node} "qm reboot ${local.new_vmid}"
    EOT
  }
}

###############################################################################
# Destroy Old VM After Successful Cutover
###############################################################################

resource "null_resource" "destroy_old" {
  depends_on = [null_resource.cutover]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Destroying old VM ${var.old_vm_id}..."
      ssh root@${var.pm_node} "qm destroy ${var.old_vm_id}"
    EOT
  }
}
