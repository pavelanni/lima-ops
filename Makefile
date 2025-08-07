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
	@echo "Legacy Shell Script Automation (Battle-tested)"
	@echo "=============================================="
	@echo "Based on proven scripts from lima_templates repository"
	@echo
	@echo "Quick Start:"
	@echo "  legacy/scripts/quick_cluster.sh -n 3 -d 2 -s 20GiB    # 3-node cluster"
	@echo "  legacy/scripts/quick_cluster.sh -h                    # Show help"
	@echo
	@echo "Individual Scripts:"
	@echo "  Disk Management:"
	@echo "    legacy/scripts/create_disks.sh -n 4 -s 50GiB       # Create storage disks"
	@echo "    legacy/scripts/mount_disks.sh                      # Mount disks (run in VM)"
	@echo
	@echo "  Cluster Management:"
	@echo "    legacy/scripts/create_lima_cluster.sh -t template  # Create VM cluster"
	@echo "    legacy/scripts/delete_lima_cluster.sh -p prefix    # Delete cluster"
	@echo
	@echo "  MinIO Setup:"
	@echo "    legacy/scripts/setup_minio_users.sh -n 3           # Setup MinIO users"
	@echo
	@echo "Templates:"
	@echo "  legacy/templates/rocky-server.yaml     # Rocky Linux 9 server"
	@echo "  legacy/templates/rocky-client.yaml     # Rocky Linux 9 client with tools"
	@echo
	@echo "Documentation:"
	@echo "  docs/legacy/                           # Legacy script documentation"
	@echo
	@echo "Note: These are proven scripts from production MinIO deployments"

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