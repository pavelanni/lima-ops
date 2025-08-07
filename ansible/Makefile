# Lima Ansible Kubernetes Cluster Management

CLUSTER_NAME ?= demo-k8s
CONFIG_FILE ?= vars/cluster_config.yml
INVENTORY_FILE = ../inventory/$(CLUSTER_NAME).ini

# Get deployment type from config file
DEPLOYMENT_TYPE = $(shell grep -A1 '^deployment:' $(CONFIG_FILE) | grep 'type:' | cut -d'"' -f2 | tr -d ' ')

.PHONY: help provision configure destroy clean status inventory

help: ## Show this help message
	@echo "Lima Ansible Cluster Management (Kubernetes & Bare-metal MinIO)"
	@echo "Usage: make <target> [CONFIG_FILE=path] [CLUSTER_NAME=name]"
	@echo
	@echo "Config File Options:"
	@echo "  CONFIG_FILE=vars/dev-small.yml        # Small development cluster"
	@echo "  CONFIG_FILE=vars/prod-large.yml       # Large production cluster"
	@echo "  CONFIG_FILE=vars/baremetal-simple.yml # Simple bare-metal MinIO"
	@echo "  CONFIG_FILE=vars/cluster_config.yml    # Default Kubernetes cluster"
	@echo "  CONFIG_FILE=vars/baremetal_config.yml  # Default bare-metal cluster"
	@echo
	@echo "Current Configuration:"
	@echo "  CONFIG_FILE: $(CONFIG_FILE)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  DEPLOYMENT_TYPE: $(DEPLOYMENT_TYPE) (from config file)"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

show-config: ## Show current configuration
	@echo "Current Configuration:"
	@echo "  CONFIG_FILE: $(CONFIG_FILE)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"
	@echo "  DEPLOYMENT_TYPE: $(DEPLOYMENT_TYPE) (from config file)"
	@echo "  INVENTORY_FILE: $(INVENTORY_FILE)"

choose-deployment: ## Guide to choose deployment type
	ansible-playbook playbooks/utilities/choose_deployment.yml

provision: ## Provision Lima VMs and generate inventory
	ansible-playbook playbooks/infrastructure/provision_vms.yml -e "cluster_name_override=$(CLUSTER_NAME)" -e "config_file=$(CONFIG_FILE)"

configure: ## Configure VMs (requires existing inventory)
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "Inventory file not found: $(INVENTORY_FILE)"; \
		echo "Run 'make provision' first or 'make inventory' to regenerate"; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY_FILE) playbooks/configuration/configure_vms.yml

inventory: ## Generate inventory file without provisioning
	ansible-playbook playbooks/configuration/generate_inventory.yml -e "cluster_name_override=$(CLUSTER_NAME)" -e "config_file=$(CONFIG_FILE)"

create-disks: ## Create all disks for the cluster
	ansible-playbook playbooks/infrastructure/manage_disks.yml -e "cluster_name_override=$(CLUSTER_NAME)" -e "config_file=$(CONFIG_FILE)"

mount-disks: ## Mount additional disks on VMs
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "Inventory file not found: $(INVENTORY_FILE)"; \
		echo "Run 'make provision' first"; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY_FILE) playbooks/configuration/mount_disks.yml

list-disks: ## List existing Lima disks
	limactl disk ls

validate: ## Validate cluster configuration before deployment
	ansible-playbook playbooks/infrastructure/validate_setup.yml -e "config_file=$(CONFIG_FILE)"

full-setup: validate create-disks provision configure mount-disks deploy ## Complete cluster setup with validation

deploy: ## Deploy application layer (K8s or bare-metal MinIO)
ifeq ($(DEPLOYMENT_TYPE),baremetal)
	@echo "Deploying bare-metal MinIO cluster..."
	ansible-playbook -i $(INVENTORY_FILE) playbooks/baremetal/deploy_baremetal_minio.yml
else
	@echo "Deploying Kubernetes-based MinIO cluster..."
	ansible-playbook playbooks/kubernetes/deploy_kubernetes_minio.yml
endif

deploy-baremetal: ## Deploy bare-metal MinIO cluster
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "Inventory file not found: $(INVENTORY_FILE)"; \
		echo "Run 'make provision' first"; \
		exit 1; \
	fi
	ansible-playbook -i $(INVENTORY_FILE) playbooks/baremetal/deploy_baremetal_minio.yml

deploy-kubernetes: ## Deploy Kubernetes-based MinIO
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "Inventory file not found: $(INVENTORY_FILE)"; \
		echo "Run 'make provision' first"; \
		exit 1; \
	fi
	ansible-playbook playbooks/kubernetes/deploy_kubernetes_minio.yml

status: ## Show Lima VM status
	limactl list

destroy: ## Destroy all VMs for the cluster
	@echo "Destroying VMs for cluster: $(CLUSTER_NAME)"
	@for vm in $$(limactl list -q | grep "^$(CLUSTER_NAME)-" || true); do \
		echo "Stopping and deleting $$vm"; \
		limactl stop $$vm 2>/dev/null || true; \
		limactl delete $$vm 2>/dev/null || true; \
	done

clean: ## Clean generated files
	rm -rf ../inventory/
	rm -rf ~/.lima/$(CLUSTER_NAME)-*

syntax-check: ## Check Ansible syntax
	ansible-playbook --syntax-check playbooks/infrastructure/provision_vms.yml
	ansible-playbook --syntax-check playbooks/configuration/configure_vms.yml
	ansible-playbook --syntax-check playbooks/configuration/generate_inventory.yml
	ansible-playbook --syntax-check playbooks/configuration/mount_disks.yml
	ansible-playbook --syntax-check playbooks/baremetal/deploy_baremetal_minio.yml
	ansible-playbook --syntax-check playbooks/kubernetes/deploy_kubernetes_minio.yml
	ansible-playbook --syntax-check playbooks/kubernetes/install_k3s.yml
	ansible-playbook --syntax-check playbooks/infrastructure/validate_setup.yml

dry-run: ## Run provision in check mode (safe - won't create VMs)
	@echo "Running in check mode - no VMs will be created"
	ansible-playbook --check --diff playbooks/infrastructure/provision_vms.yml

dry-run-configure: ## Run configuration in check mode (safe - won't modify VMs)
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "Inventory file not found: $(INVENTORY_FILE)"; \
		echo "Run 'make inventory' first"; \
		exit 1; \
	fi
	@echo "Running configuration check mode - no changes will be made"
	ansible-playbook --check --diff -i $(INVENTORY_FILE) playbooks/configuration/configure_vms.yml

# Usage Examples:
# Using configuration files (deployment type is defined in config):
#   make full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev
#   make full-setup CONFIG_FILE=vars/prod-large.yml CLUSTER_NAME=production  
#   make full-setup CONFIG_FILE=vars/baremetal-simple.yml CLUSTER_NAME=storage
#
# Using default config:
#   make full-setup CLUSTER_NAME=my-cluster  # Uses vars/cluster_config.yml
#
# Just infrastructure:
#   make provision configure CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=my-cluster