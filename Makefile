###############################################################################
# Technitium GitOps Makefile
#
# Default behavior: show help
###############################################################################
.DEFAULT_GOAL := help

REPO_DIR := /opt/infra/technitium
ANSIBLE := ansible-playbook

# Colors
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
RESET  := \033[0m

###############################################################################
# Help Target
###############################################################################
help: ## Show this help menu
	@echo ""
	@echo "$(BLUE)Available Makefile Commands$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?##' Makefile | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

###############################################################################
# Ansible Operations
###############################################################################
install: ## Run Technitium install playbook
	$(ANSIBLE) install-technitium.yaml

configure: ## Run Technitium configure playbook
	$(ANSIBLE) configure-technitium.yaml

rebuild: ## Run full Ansible rebuild (install + configure)
	$(ANSIBLE) install-technitium.yaml
	$(ANSIBLE) configure-technitium.yaml

###############################################################################
# Zone Validation
###############################################################################
validate-zones: ## Validate DNS zone files using named-checkzone
	@echo "Validating zone files..."
	@for z in dns/zones/*.zone; do \
		origin=$$(basename "$$z" .zone); \
		echo "Checking $$z"; \
		named-checkzone "$$origin" "$$z"; \
	done


###############################################################################
# Git Operations
###############################################################################
pull: ## Pull latest infra repo changes
	cd $(REPO_DIR) && git pull --rebase

###############################################################################
# Terraform Deployment
###############################################################################
deploy: ## Deploy Technitium DNS via Terraform
	cd terraform && terraform init && terraform apply -auto-approve

###############################################################################
# Developer Environment
###############################################################################
verify-dev: ## Verify developer machine prerequisites
	./verify-dev.sh

install-dev: ## Bootstrap developer machine (Linux)
	./bootstrap-dev.sh

###############################################################################
# Secret Scanning
###############################################################################
scan-secrets: ## Run detect-secrets and git-secrets scans
	detect-secrets scan > .detect-secrets.json
	git secrets --scan

verify-secrets: ## Validate secrets baseline
	detect-secrets-hook --baseline .detect-secrets.json
	git secrets --scan

###############################################################################
# Linting
###############################################################################
lint: ## Run all linters (shell, YAML, Terraform)
	@echo "$(BLUE)Linting shell scripts...$(RESET)"
	@shellcheck dns/scripts/*.sh || true
	@shellcheck technitium/terraform/scripts/*.sh || true

	@echo "$(BLUE)Linting YAML...$(RESET)"
	@yamllint technitium/ansible || true
	@yamllint technitium/cloud-init || true

	@echo "$(BLUE)Linting Terraform...$(RESET)"
	@cd technitium/terraform && terraform fmt -check && terraform validate

	@echo "$(GREEN)Lint complete.$(RESET)"

###############################################################################
# PHONY DECLARATIONS
###############################################################################
.PHONY: install configure validate-zones rebuild pull deploy \
		verify-dev install-dev scan-secrets verify-secrets lint help
