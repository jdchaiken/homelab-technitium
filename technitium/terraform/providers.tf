###############################################################################
# Providers for Technitium GitOps Terraform Module
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "2.9.14"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.3.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "2.3.1"
    }
  }
}

###############################################################################
# Provider Configuration
###############################################################################

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_user         = var.pm_user
  pm_password     = var.pm_password
  pm_tls_insecure = true
}

provider "null" {}

provider "external" {}
