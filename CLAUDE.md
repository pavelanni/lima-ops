# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Ansible-based project for provisioning and configuring clusters using Lima VMs.
The project supports two deployment types:

1. **Kubernetes-based clusters** - For container orchestration and microservices
1. **Bare-metal MinIO clusters** - For high-performance object storage

The project separates infrastructure provisioning (VMs, disks, networking) from application deployment,
allowing you to choose your deployment type after creating the infrastructure.

## Architecture

The project follows a three-phase approach:

1. **Infrastructure Provisioning Phase** (runs on localhost):
   - Creates Lima disks with flexible naming
   - Creates Lima VM configuration files from Jinja2 templates
   - Starts Lima VMs with specified resources (CPU, memory, disk)
   - Generates inventory files for the cluster

1. **VM Configuration Phase** (runs on Lima VMs):
   - Configures disk partitioning, formatting, and mounting
   - Installs common packages and tools
   - Prepares VMs for application deployment

1. **Application Deployment Phase** (runs on Lima VMs):
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

### Using Shell Scripts (Recommended)

**Interactive Setup:**

```bash
./scripts/interactive-setup.sh    # Guided setup wizard
```

**Complete Workflows:**

```bash
# Using specific configuration files (deployment type defined in config)
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev
./scripts/deploy-cluster.sh --config ansible/vars/prod-large.yml --name production
./scripts/deploy-cluster.sh --config ansible/vars/baremetal-simple.yml --name storage

# Using default configuration
./scripts/deploy-cluster.sh --config ansible/vars/cluster_config.yml --name mycluster
```

**Step-by-step Workflow:**

```bash
# With specific config file
./scripts/deploy-cluster.sh validate --config ansible/vars/dev-small.yml --name dev
./scripts/deploy-cluster.sh create-disks --config ansible/vars/dev-small.yml --name dev
./scripts/deploy-cluster.sh provision --config ansible/vars/dev-small.yml --name dev
./scripts/deploy-cluster.sh configure --name dev
./scripts/deploy-cluster.sh mount-disks --name dev
./scripts/deploy-cluster.sh deploy --name dev
```

**Management Commands:**

```bash
./scripts/manage-cluster.sh list              # List all clusters
./scripts/manage-cluster.sh status CLUSTER    # Check cluster status
./scripts/manage-cluster.sh ssh CLUSTER NODE  # SSH into a VM
./scripts/manage-cluster.sh logs CLUSTER NODE # Show VM logs
./scripts/manage-cluster.sh destroy CLUSTER   # Destroy cluster
./scripts/manage-cluster.sh cleanup           # Clean up orphaned resources
```

### Manual Ansible Commands

```bash
# Provision VMs and generate inventory
ansible-playbook ansible/playbooks/infrastructure/provision_vms.yml \
  -e config_file=ansible/vars/dev-small.yml -e cluster_name=dev

# Configure VMs using generated inventory
ansible-playbook -i inventory/dev.ini ansible/playbooks/configuration/configure_vms.yml

# Generate inventory without provisioning
ansible-playbook ansible/playbooks/configuration/generate_inventory.yml \
  -e config_file=ansible/vars/dev-small.yml -e cluster_name=dev

# Syntax checking
ansible-playbook --syntax-check ansible/playbooks/infrastructure/provision_vms.yml

# Safe dry-run (won't create VMs)
./scripts/deploy-cluster.sh --dry-run --config ansible/vars/dev-small.yml --name dev
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

### Troubleshooting

**Lima Disk Resize Error ("diffDisk: Shrinking is currently unavailable")**

This error occurs when there's a disk size mismatch between your configuration file and existing Lima VMs. Lima doesn't support disk resizing, so the sizes must match exactly.

**Root Cause:** Configuration file specifies different disk size than existing VM
- Example: Config says `disk_size: "8GiB"` but existing VM has 10GiB

**Solution:** The new shell scripts automatically detect and prevent this issue:

```bash
# The validation will show:
ERROR: Disk size mismatch for VM 'dev-worker-01':
  Configuration file: 8GiB  
  Existing VM: 10GiB

Lima does not support disk resizing. Please either:
1. Update the configuration file to match existing VM: disk_size: "10GiB"
2. Destroy the existing VM and recreate: ./scripts/deploy-cluster.sh destroy --name dev
```

**Prevention:** Always run validation before deployment:
```bash
./scripts/deploy-cluster.sh validate --config CONFIG_FILE --name CLUSTER_NAME
```

### AIStor License Requirements

**IMPORTANT**: AIStor (Commercial MinIO) requires a valid SUBNET license.

1. **Get License**: Visit [SUBNET Portal](https://subnet.min.io) to obtain your license
1. **Configure License**: Set `aistor.license` in your configuration file
1. **Keep Secure**: The license is stored in values files with restricted permissions

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

- **Check mode protection**: `--dry-run` safely shows what would happen without creating VMs
- **Shell command protection**: Lima commands are skipped in check mode to prevent accidental VM creation
- **Disk management safety**: Disk operations are properly handled in check mode
- **Configuration validation**: Pre-deployment validation checks requirements before deployment

## Current Status (Last updated: 2025-10-02)

✅ **Complete:**
- **Shell Script Migration**: Converted from Makefile-based to user-friendly shell scripts (August 2025)
- **Interactive Setup**: Added wizard-based deployment with comprehensive error handling
- **Disk Size Validation**: Added validation to prevent Lima disk resize conflicts
- Infrastructure provisioning and VM creation
- Lima VM disk mounting issues resolved (switched to raw format)
- Cluster-node naming convention and override functionality
- SSH connectivity using Lima's native SSH config files
- Dynamic user detection for portable Ansible execution
- Comprehensive disk mounting strategy implemented
- Project reorganization following Ansible best practices
- Constitution-based governance model (v1.0.0)
- Code quality improvements with shellcheck validation

✅ **Recent Additions (October 2025):**
- **Project Constitution**: Established six core principles for governance
  - Declarative Configuration
  - Validation-First Deployment
  - Separation of Concerns
  - Safe Automation
  - Shell Script Simplicity
  - Idempotent Operations

- **Code Quality Improvements**:
  - Added `set -euo pipefail` safety flags to all shell scripts
  - Shellcheck validation passing on all scripts
  - Fixed style warnings and potential bugs
  - Improved error handling consistency

✅ **Shell Script Features:**
- `scripts/deploy-cluster.sh` - Main orchestration with step-by-step or full workflows
- `scripts/interactive-setup.sh` - Interactive wizard for guided deployment
- `scripts/manage-cluster.sh` - Cluster management utilities (status, SSH, logs, cleanup)
- `scripts/lib/` - Shared utilities with error handling, validation, and configuration management

🔄 **Migration Notes:**
- **Old Makefile commands replaced:**
  - Old: `make full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev`
  - **New:** `./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev`
  - **Or:** `./scripts/interactive-setup.sh` (recommended for beginners)
- All previous functionality preserved with improved usability
- Documentation updated to reflect shell script approach

🎯 **Ready for Production Use:**
- All core features implemented and tested
- Comprehensive documentation for both users and developers
- Safe automation with validation and error handling
- Support for both Kubernetes and bare-metal MinIO deployments
