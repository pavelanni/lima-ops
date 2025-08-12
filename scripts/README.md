# Lima-Ops Shell Scripts

This directory contains shell scripts that replace the Makefile-based workflow with more flexible and user-friendly automation.

## Quick Start

### Option 1: Interactive Setup (Recommended for beginners)
```bash
./scripts/interactive-setup.sh
```

### Option 2: Direct Command Line
```bash
# Quick deployment
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev

# Dry run (show what would happen)
./scripts/deploy-cluster.sh --dry-run --config ansible/vars/dev-small.yml --name dev
```

## Available Scripts

### Main Scripts

- **`deploy-cluster.sh`** - Main orchestration script for cluster deployment
- **`interactive-setup.sh`** - Interactive wizard for guided setup
- **`manage-cluster.sh`** - Cluster management utilities

### Core Commands

#### deploy-cluster.sh
```bash
# Full deployment workflow
./scripts/deploy-cluster.sh --config CONFIG_FILE --name CLUSTER_NAME

# Individual steps
./scripts/deploy-cluster.sh provision --config CONFIG_FILE --name CLUSTER_NAME
./scripts/deploy-cluster.sh configure --name CLUSTER_NAME
./scripts/deploy-cluster.sh deploy --name CLUSTER_NAME

# Other operations
./scripts/deploy-cluster.sh validate --config CONFIG_FILE --name CLUSTER_NAME
./scripts/deploy-cluster.sh status --name CLUSTER_NAME
./scripts/deploy-cluster.sh destroy --name CLUSTER_NAME
./scripts/deploy-cluster.sh list-configs
```

#### manage-cluster.sh
```bash
# List all clusters
./scripts/manage-cluster.sh list

# Show detailed cluster status
./scripts/manage-cluster.sh status CLUSTER_NAME

# SSH into a VM
./scripts/manage-cluster.sh ssh CLUSTER_NAME VM_NAME

# Show VM logs
./scripts/manage-cluster.sh logs CLUSTER_NAME VM_NAME

# Show port forwarding info
./scripts/manage-cluster.sh port-forward

# Destroy a specific cluster
./scripts/manage-cluster.sh destroy CLUSTER_NAME

# Clean up orphaned resources
./scripts/manage-cluster.sh cleanup
```

## Configuration Files

Available configuration files are in `ansible/vars/`:

- `dev-small.yml` - Small development cluster (1 control-plane + 1 worker)
- `prod-large.yml` - Large production cluster (3 control-plane + 4 workers)
- `baremetal-simple.yml` - Simple bare-metal MinIO (4 nodes)
- `cluster_config.yml` - Default Kubernetes cluster
- `baremetal_config.yml` - Default bare-metal cluster

Use `./scripts/deploy-cluster.sh list-configs` to see all available options.

## Cluster Naming Requirements

**Important:** Cluster names cannot contain dashes (`-`) as they interfere with VM name parsing.

✅ **Valid cluster names:**
- `dev` 
- `production`
- `test123`
- `storage`

❌ **Invalid cluster names:**
- `dev-cluster` 
- `test-env`
- `prod-2024`

## Examples

### Deploy Development Cluster
```bash
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev
```

### Deploy Production Cluster
```bash
./scripts/deploy-cluster.sh --config ansible/vars/prod-large.yml --name production
```

### Deploy Bare-metal MinIO
```bash
./scripts/deploy-cluster.sh --config ansible/vars/baremetal-simple.yml --name storage
```

### Step-by-step Deployment
```bash
# 1. Validate configuration
./scripts/deploy-cluster.sh validate --config ansible/vars/dev-small.yml --name dev

# 2. Create disks
./scripts/deploy-cluster.sh create-disks --config ansible/vars/dev-small.yml --name dev

# 3. Provision VMs
./scripts/deploy-cluster.sh provision --config ansible/vars/dev-small.yml --name dev

# 4. Configure VMs
./scripts/deploy-cluster.sh configure --name dev

# 5. Mount disks
./scripts/deploy-cluster.sh mount-disks --name dev

# 6. Deploy applications
./scripts/deploy-cluster.sh deploy --name dev
```

### Cluster Management
```bash
# List all clusters
./scripts/manage-cluster.sh list

# Check cluster status
./scripts/manage-cluster.sh status dev

# SSH into control plane
./scripts/manage-cluster.sh ssh dev control-plane-01

# Check VM logs
./scripts/manage-cluster.sh logs dev worker-01

# Show port forwarding
./scripts/manage-cluster.sh port-forward

# Clean up stopped VMs and orphaned disks
./scripts/manage-cluster.sh cleanup

# Destroy cluster (two options)
./scripts/deploy-cluster.sh destroy --name dev
./scripts/manage-cluster.sh destroy dev
```

## Features

### Advantages over Makefile approach

1. **Better error handling** - Proper bash error handling and user feedback
2. **Interactive guidance** - Prompts, confirmations, and progress indicators
3. **Flexible parameters** - No path resolution issues between directories
4. **Rich output** - Colored output, progress bars, and clear status messages
5. **Modular design** - Reusable functions in `lib/` directory
6. **Comprehensive validation** - Pre-flight checks and system requirements
7. **Cluster management** - Built-in utilities for cluster operations

### Safety Features

- **Dry run mode** - Preview changes before execution
- **Pre-deployment validation** - Check requirements and conflicts
- **Confirmation prompts** - Prevent accidental destructive operations
- **Resource cleanup** - Handle orphaned VMs and disks

### Debugging

Enable verbose output for debugging:
```bash
./scripts/deploy-cluster.sh --verbose --config CONFIG_FILE --name CLUSTER_NAME
./scripts/manage-cluster.sh --verbose COMMAND
```

## Troubleshooting

### Common Issues

1. **Configuration not found**
   ```bash
   # List available configurations
   ./scripts/deploy-cluster.sh list-configs
   ```

2. **Lima VMs already exist**
   ```bash
   # Check existing clusters
   ./scripts/manage-cluster.sh list
   
   # Destroy conflicting cluster
   ./scripts/deploy-cluster.sh destroy --name CLUSTER_NAME
   ```

3. **Disk resize errors**
   ```bash
   # Clean up existing disks
   ./scripts/manage-cluster.sh cleanup
   ```

4. **Permission issues**
   ```bash
   # Ensure scripts are executable
   chmod +x scripts/*.sh
   ```

5. **Lima VM creation failures** (network timeouts, basedisk errors)
   ```bash
   # Option 1: Leverage Ansible idempotency - simply rerun the provision step
   ./scripts/deploy-cluster.sh provision --config CONFIG_FILE --name CLUSTER_NAME
   
   # Option 2: Manual Lima start (if config file already exists)
   limactl start ~/.lima/CLUSTER_NAME-NODE_NAME/lima.yaml
   
   # Option 3: Clean up failed VM and retry
   limactl delete CLUSTER_NAME-NODE_NAME 2>/dev/null || true
   ./scripts/deploy-cluster.sh provision --config CONFIG_FILE --name CLUSTER_NAME
   
   # Option 4: Clear Lima cache if persistent network issues
   rm -rf ~/.lima/_cache/
   ```

### Advanced Recovery

For experienced users, the individual Ansible playbooks can be run directly:

```bash
# Provision VMs only (idempotent)
ansible-playbook -i inventory/ ansible/playbooks/infrastructure/provision_vms.yml \
  -e config_file=CONFIG_FILE -e cluster_name=CLUSTER_NAME

# Configure existing VMs (idempotent) 
ansible-playbook -i inventory/CLUSTER_NAME.ini ansible/playbooks/configuration/configure_vms.yml

# Deploy applications only (idempotent)
ansible-playbook -i inventory/CLUSTER_NAME.ini ansible/playbooks/kubernetes/deploy_kubernetes_minio.yml
```

### Getting Help

- Use `--help` flag on any script for detailed usage information
- Check the main project README.md for overall documentation
- Use `--dry-run` to preview operations without making changes