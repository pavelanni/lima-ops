# Lima-Ops: Comprehensive Lima VM Management
# Supports both modern Ansible automation and legacy shell scripts

# Default to Ansible approach
APPROACH ?= ansible
CLUSTER_NAME ?= demo-k8s
CONFIG_FILE ?= vars/cluster_config.yml

.PHONY: help ansible-help legacy-help

help: ## Show main help menu
	@echo "Lima-Ops: Comprehensive Lima VM Management"
	@echo "==========================================="
	@echo
	@echo "Choose your approach:"
	@echo "  make ansible-help    # Modern Ansible automation (recommended)"
	@echo "  make legacy-help     # Shell script automation (battle-tested)"
	@echo
	@echo "Quick Start:"
	@echo "  make ansible CONFIG_FILE=ansible/vars/dev-small.yml CLUSTER_NAME=dev"
	@echo
	@echo "Project Structure:"
	@echo "  ansible/      - Modern Infrastructure-as-Code approach"
	@echo "  legacy/       - Proven shell scripts and templates"
	@echo "  docs/         - Documentation and guides"
	@echo "  examples/     - Usage examples"
	@echo

ansible-help: ## Show Ansible automation help
	@echo "Delegating to Ansible automation..."
	@cd ansible && make help

legacy-help: ## Show legacy scripts help
	@echo "Legacy Shell Script Automation"
	@echo "=============================="
	@echo "Coming soon: Shell script automation from lima_templates"
	@echo
	@echo "Available once migration is complete:"
	@echo "  make legacy-provision CLUSTER_SIZE=3"
	@echo "  make legacy-storage"
	@echo "  make legacy-minio"

# Delegate to Ansible by default
ansible: ## Run Ansible automation
	@cd ansible && make $(filter-out ansible,$(MAKECMDGOALS))

# Legacy approach (to be implemented)
legacy: ## Run legacy shell scripts
	@echo "Legacy approach not yet migrated. Use 'make ansible' for now."

# Allow direct Ansible commands
%: 
	@if [ "$(APPROACH)" = "ansible" ]; then \
		cd ansible && make $@; \
	else \
		echo "Legacy approach not yet available. Use 'make ansible $@'"; \
	fi