# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Ansible-based project for provisioning and configuring clusters using Lima VMs. The project supports two deployment types:

1. **Kubernetes-based clusters** - For container orchestration and microservices
2. **Bare-metal MinIO clusters** - For high-performance object storage

The project separates infrastructure provisioning (VMs, disks, networking) from application deployment, allowing you to choose your deployment type after creating the infrastructure.

## Architecture

The project follows a three-phase approach:

1. **Infrastructure Provisioning Phase** (runs on localhost):
   - Creates Lima disks with flexible naming
   - Creates Lima VM configuration files from Jinja2 templates
   - Starts Lima VMs with specified resources (CPU, memory, disk)
   - Generates inventory files for the cluster

2. **VM Configuration Phase** (runs on Lima VMs):
   - Configures disk partitioning, formatting, and mounting
   - Installs common packages and tools
   - Prepares VMs for application deployment

3. **Application Deployment Phase** (runs on Lima VMs):
   - **Kubernetes path**: Installs K8s components, initializes cluster
   - **Bare-metal MinIO path**: Installs MinIO, configures distributed storage

### Key Files Structure

**Configuration Files:**

- `vars/cluster_config.yml` - Kubernetes cluster configuration
- `vars/baremetal_config.yml` - Bare-metal MinIO cluster configuration

**Infrastructure Playbooks:**

- `provision_vms.yml` - Creates Lima VMs and generates inventory
- `configure_vms.yml` - Configures VMs with disk management
- `manage_disks.yml` - Creates and manages Lima disks

**Application Deployment:**

- `deploy_baremetal_minio.yml` - Installs bare-metal MinIO cluster
- `deploy_kubernetes_minio.yml` - Installs Kubernetes cluster with AIStor (Commercial MinIO)
- `install_k3s.yml` - K3s Kubernetes installation
- `install_k8s_prerequisites.yml` - cert-manager, ingress-nginx, krew
- `install_directpv.yml` - DirectPV storage provisioning
- `install_minio_operator.yml` - AIStor Operator and Object Store (Helm-based)
- `configure_minio_ingress.yml` - Ingress configuration for AIStor
- `verify_k8s_minio.yml` - Installation verification

**Utilities:**

- `validate_setup.yml` - Pre-deployment validation
- `choose_deployment.yml` - Interactive deployment guide

### Configuration Pattern

The project uses a declarative configuration approach with multiple configuration files:

**Available Configuration Files:**
- `vars/cluster_config.yml` - Default Kubernetes cluster (3 nodes)
- `vars/baremetal_config.yml` - Default bare-metal MinIO cluster
- `vars/dev-small.yml` - Small development cluster (1 control-plane + 1 worker)
- `vars/prod-large.yml` - Large production cluster (3 control-plane + 4 workers with HA)
- `vars/baremetal-simple.yml` - Simple bare-metal MinIO (4 nodes)

**Configuration Structure:**
- `kubernetes_cluster.nodes` array defines all VMs with their specifications
- Each node has a `role` (control-plane or worker) and resource allocations
- Additional disks are configured per-node with custom mount points
- `deployment.type` field determines application layer (kubernetes vs baremetal)
- Single source of truth: all settings including deployment type in config file

## Common Commands

### Using the Makefile (Recommended)

**Choose Your Deployment:**

```bash
make choose-deployment    # Interactive guide to deployment options
```

**Complete Workflows:**

```bash
# Using specific configuration files (deployment type defined in config)
make full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev
make full-setup CONFIG_FILE=vars/prod-large.yml CLUSTER_NAME=production
make full-setup CONFIG_FILE=vars/baremetal-simple.yml CLUSTER_NAME=storage

# Using default configuration
make full-setup CLUSTER_NAME=my-cluster  # Uses vars/cluster_config.yml

# Infrastructure only
make provision configure CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=my-cluster
```

**Step-by-step Workflow:**

```bash
# With specific config file
make validate CONFIG_FILE=vars/dev-small.yml
make create-disks CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev
make provision CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev
make configure CLUSTER_NAME=dev
make mount-disks CLUSTER_NAME=dev
make deploy CLUSTER_NAME=dev

# Using default config
make validate
make create-disks CLUSTER_NAME=my-cluster
make provision CLUSTER_NAME=my-cluster
make configure CLUSTER_NAME=my-cluster
make mount-disks CLUSTER_NAME=my-cluster
make deploy CLUSTER_NAME=my-cluster
```

**Application-specific Deployment:**

```bash
make deploy-baremetal     # Deploy bare-metal MinIO
make deploy-kubernetes    # Deploy Kubernetes apps
```

**Management Commands:**

```bash
make status          # Check VM status
make list-disks      # List Lima disks
make mount-disks     # Mount additional disks on VMs
make show-config     # Show current configuration
make destroy         # Destroy cluster
make help            # Show all available commands
```

### Manual Ansible Commands

```bash
# Provision VMs and generate inventory
ansible-playbook provision_vms.yml

# Configure VMs using generated inventory
ansible-playbook -i inventory/demo-k8s.ini configure_vms.yml

# Generate inventory without provisioning
ansible-playbook generate_inventory.yml

# Syntax checking
make syntax-check

# Safe dry-run (won't create VMs)
make dry-run
```

### Lima VM Management

```bash
# List Lima VMs
limactl list

# Stop a VM
limactl stop <vm-name>

# Delete a VM
limactl delete <vm-name>

# SSH into a VM
limactl shell <vm-name>
```

## Development Notes

### Project Structure

- `provision_vms.yml` - Creates Lima VMs and generates inventory
- `configure_vms.yml` - Configures existing VMs with disk management
- `manage_disks.yml` - Creates and manages Lima disks for the cluster
- `validate_setup.yml` - Validates cluster configuration before deployment
- `generate_inventory.yml` - Generates static inventory file
- `Makefile` - Provides convenient commands for common operations

### VM Configuration

- VMs are configured with vz vmType for Apple Silicon (aarch64)
- SSH access uses Lima's default 'lima' user
- Inventory files are generated dynamically based on cluster config

### Disk Management

- Comprehensive disk management based on user's shell script approach
- Smart disk detection: excludes vda (system disk) and cidata labeled disks
- Properly unmounts existing Lima auto-mounted disks before processing
- Cleans existing filesystem signatures with wipefs
- Removes old fstab entries to prevent conflicts
- Creates fresh GPT partition tables and formats with XFS filesystem
- UUID-based fstab entries for reliable persistent mounting
- Mount points follow `/mnt/minio{number}` pattern for MinIO compatibility
- Creates MinIO data directories automatically at `/mnt/minio{number}/data`
- Handles both fresh disks and previously mounted disks correctly

### Inventory Management

- Static inventory files are generated in `inventory/` directory
- Inventory includes host variables for node-specific configuration
- Supports multiple clusters by using cluster name as inventory filename

### Deployment Types

**Bare-metal MinIO:**

- Direct MinIO installation on VMs (no containers)
- Better performance, simpler architecture
- Distributed storage across multiple nodes
- Automatic MinIO user/service configuration
- Good for: Pure object storage use cases

**Kubernetes-based:**

- Container orchestration platform with AIStor (Commercial MinIO)
- K3s lightweight Kubernetes distribution
- Helm-based AIStor installation (enterprise-grade)
- DirectPV for storage provisioning
- Ingress-based external access
- Built-in SSL/TLS and certificate management
- Support for multiple applications
- Better scaling and management
- Integration with K8s ecosystem
- Enterprise features and commercial support
- Good for: Mixed workloads, microservices, enterprise environments

### Integration Points

- Flexible deployment type selection
- Shared infrastructure provisioning for both types
- MinIO data directories are automatically created on data disks
- Dynamic port forwarding for MinIO (API: 9100+, Console: 9101+)
- Kubernetes API port forwarding for control plane nodes
- Configuration centralized in vars/ directory

### AIStor License Requirements

**IMPORTANT**: AIStor (Commercial MinIO) requires a valid SUBNET license.

1. **Get License**: Visit [SUBNET Portal](https://subnet.min.io) to obtain your license
2. **Configure License**: Set `aistor.license` in your configuration file
3. **Keep Secure**: The license is stored in values files with restricted permissions

Example configuration:

```yaml
aistor:
  license: "your-subnet-license-string-here"
```

Without a valid license, the AIStor operator installation will fail.

### Key Features from Shell Project

- **Disk Management**: Automated disk creation with flexible naming (`minio-<node>-<disk>`)
- **Port Forwarding**: Dynamic port allocation (MinIO API/Console, K8s API)
- **Pre-validation**: Configuration validation before deployment
- **Package Installation**: Common tools (net-tools, vim, bc, lsof)
- **Error Handling**: Graceful handling of existing resources

### Safety Features

- **Check mode protection**: `make dry-run` safely shows what would happen without creating VMs
- **Shell command protection**: Lima commands are skipped in check mode to prevent accidental VM creation
- **Disk management safety**: Disk operations are properly handled in check mode
- **Configuration validation**: `make validate` checks requirements before deployment

## Current Status (Last updated: 2025-07-12)

✅ **Complete:**
- Infrastructure provisioning and VM creation
- Lima VM disk mounting issues resolved (switched to raw format)
- Cluster-node naming convention and override functionality
- SSH connectivity using Lima's native SSH config files
- Dynamic user detection for portable Ansible execution
- Comprehensive disk mounting strategy implemented
- Project reorganization following Ansible best practices

✅ **Recent Additions:**
- Created `tasks/mount_additional_disks.yml` for smart disk detection (excludes vda and cidata)
- Created `tasks/process_single_disk.yml` for complete disk lifecycle management
- Created `playbooks/configuration/mount_disks.yml` playbook
- Added `make mount-disks` command to Makefile
- Updated `full-setup` workflow to include disk mounting
- Implemented comprehensive disk management: unmount → clean → reformat → remount
- Based on user's proven shell script approach with full Lima integration

🔄 **Next Steps:**
- ✅ Disk mounting tested and working perfectly on lab cluster
- Proceed with MinIO or Kubernetes installation 
- Deploy application layer (K8s/AIStor or bare-metal MinIO)

**Available Clusters:**
- lab cluster (lab-control-plane-01, lab-worker-01, lab-worker-02)
- SSH access via Lima SSH config files with dynamic user detection
