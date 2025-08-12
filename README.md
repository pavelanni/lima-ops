# Lima-Ops: Comprehensive Lima VM Management

A complete toolkit for provisioning and managing clusters using Lima VMs on macOS.
Features user-friendly shell script automation with comprehensive error handling,
interactive setup wizards, and rich cluster management capabilities. Supports
Kubernetes-based deployments and bare-metal MinIO clusters with enterprise-grade
storage solutions.

> **✨ New!** This project now uses intuitive shell scripts instead of Makefiles for better user experience, error handling, and flexibility. All previous functionality is preserved with improved usability.

## Overview

This project provides a comprehensive toolkit for creating development and production
clusters on your local machine using Lima VMs. It offers two complementary approaches:

### **🚀 Shell Script Automation (Recommended)**

- **User-friendly Scripts**: Interactive setup with comprehensive error handling
- **Flexible Deployment**: Step-by-step or full automation workflows
- **Rich Management**: Built-in cluster status, logs, and SSH utilities
- **Enterprise Integration**: AIStor (Commercial MinIO) support

### **⚡ Legacy Approach (Available)**

- **Direct Shell Scripts**: Proven automation scripts from production use in `legacy/`
- **Lima Templates**: Ready-to-use VM configurations
- **Quick Deployment**: Fast cluster provisioning for immediate needs

### Supported Deployments

- **Kubernetes Clusters**: Container orchestration with AIStor (Commercial MinIO)
  integration
- **Bare-metal MinIO**: High-performance object storage clusters for dedicated
  storage workloads
- **Mixed Environments**: Combine approaches based on specific needs

## Quick Start

### Prerequisites

- macOS with Apple Silicon or Intel
- [Lima](https://lima-vm.io/) installed (`brew install lima`)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
  installed (`brew install ansible`)
- At least 8GB RAM and 50GB free disk space (for development clusters)

### Installation

1. Clone this repository:

```bash
git clone https://github.com/pavelanni/lima-ops.git
cd lima-ops
```

1. Verify prerequisites:

```bash
lima --version
ansible --version
```

- Lima should be of version 1.1+
- Ansible was tested with version 2.18 (core)

### Deploy Your First Cluster

#### **Interactive Setup** (Recommended for beginners)

```bash
# Launch the interactive setup wizard
./scripts/interactive-setup.sh
```

#### **Direct Command Line** (For experienced users)

```bash
# Small development cluster (1 control-plane + 1 worker)
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev

# Check cluster status
./scripts/manage-cluster.sh status dev

# SSH into a node
./scripts/manage-cluster.sh ssh dev control-plane-01
```

#### **Available Scripts**

```bash
# Main deployment orchestration
./scripts/deploy-cluster.sh --help

# Cluster management utilities  
./scripts/manage-cluster.sh --help

# Interactive wizard
./scripts/interactive-setup.sh
```

## Configuration Options

The project includes several pre-configured cluster templates:

| Config File                        | Description          | Nodes                 | Resources           |
| ---------------------------------- | -------------------- | --------------------- | ------------------- |
| `ansible/vars/dev-small.yml`       | Small dev cluster    | 1 control + 1 worker  | 2 CPU, 2GB RAM each |
| `ansible/vars/prod-large.yml`      | Large prod cluster   | 3 control + 4 workers | 4 CPU, 8GB RAM each |
| `ansible/vars/baremetal-simple.yml`| Simple MinIO storage | 4 storage nodes       | 2 CPU, 4GB RAM each |
| `ansible/vars/cluster_config.yml`  | Default Kubernetes   | 1 control + 2 workers | Variable resources  |
| `ansible/vars/baremetal_config.yml`| Default MinIO        | Variable nodes        | Variable resources  |

## Usage

### Complete Workflows

```bash
# Development cluster
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name dev

# Production cluster  
./scripts/deploy-cluster.sh --config ansible/vars/prod-large.yml --name production

# Bare-metal storage cluster
./scripts/deploy-cluster.sh --config ansible/vars/baremetal-simple.yml --name storage

# Interactive deployment (recommended)
./scripts/interactive-setup.sh
```

### Step-by-step Deployment

```bash
# 1. Validate configuration
./scripts/deploy-cluster.sh validate --config ansible/vars/dev-small.yml --name dev

# 2. Create storage disks
./scripts/deploy-cluster.sh create-disks --config ansible/vars/dev-small.yml --name dev

# 3. Provision VMs
./scripts/deploy-cluster.sh provision --config ansible/vars/dev-small.yml --name dev

# 4. Configure VMs
./scripts/deploy-cluster.sh configure --name dev

# 5. Mount storage disks
./scripts/deploy-cluster.sh mount-disks --name dev

# 6. Deploy applications
./scripts/deploy-cluster.sh deploy --name dev
```

### Management Commands

```bash
# Show all clusters
./scripts/manage-cluster.sh list

# Show cluster status
./scripts/manage-cluster.sh status dev

# SSH into a VM
./scripts/manage-cluster.sh ssh dev control-plane-01

# Show VM logs
./scripts/manage-cluster.sh logs dev worker-01

# Destroy cluster
./scripts/deploy-cluster.sh destroy --name dev

# Get help
./scripts/deploy-cluster.sh --help
./scripts/manage-cluster.sh --help
```

## Features

### Infrastructure Management

- **Automated VM Provisioning**: Creates Lima VMs with specified resources
- **Dynamic Disk Management**: Creates, formats, and mounts additional storage disks
- **Smart Inventory Generation**: Dynamic Ansible inventory with SSH configuration
- **Multi-cluster Support**: Deploy multiple isolated clusters simultaneously

### Storage Features

- **XFS Filesystem**: High-performance filesystem for storage workloads
- **UUID-based Mounting**: Reliable disk mounting across reboots
- **Automatic Cleanup**: Handles existing mounts and filesystem signatures
- **MinIO-optimized Paths**: Storage mounted to `/mnt/minio{n}` for compatibility

### Deployment Types

- **Kubernetes**: K3s with AIStor (Commercial MinIO), DirectPV storage, ingress
- **Bare-metal MinIO**: Direct MinIO installation for maximum performance
- **Enterprise Features**: AIStor includes commercial support and advanced features

## Architecture

The project follows a three-phase deployment approach:

1. **Infrastructure Phase**: VM creation, disk provisioning, networking setup
1. **Configuration Phase**: OS configuration, disk mounting, package installation
1. **Application Phase**: Kubernetes or MinIO deployment and configuration

### Directory Structure

```text
lima-ops/
├── ansible/              # Modern Ansible automation
│   ├── playbooks/        # Infrastructure and deployment playbooks
│   ├── vars/            # Cluster configuration templates
│   ├── templates/       # Jinja2 templates
│   ├── tasks/           # Reusable Ansible tasks
│   └── Makefile         # Ansible workflow automation
├── legacy/              # Battle-tested shell scripts
│   ├── templates/       # Lima VM templates
│   └── scripts/         # Provisioning and management scripts
├── docs/                # Documentation and guides
├── examples/            # Usage examples and tutorials
└── README.md           # This file
```

## Customization

### Creating Custom Configurations

1. Copy an existing configuration:

```bash
cp vars/dev-small.yml vars/my-custom.yml
```

1. Edit the configuration:

```yaml
kubernetes_cluster:
  name: "my-custom"
  nodes:
    - name: "control-01"
      role: "control-plane"
      cpus: 4
      memory: "8GiB"
      disk_size: "40GiB"
      additional_disks:
        - name: "disk1"
          size: "100GiB"
```

1. Deploy with your custom configuration:

```bash
./scripts/deploy-cluster.sh --config ansible/vars/my-custom.yml --name custom
```

### Node Configuration Options

- **role**: `control-plane` or `worker`
- **cpus**: Number of CPU cores (1-8)
- **memory**: RAM allocation (`2GiB`, `4GiB`, `8GiB`, etc.)
- **disk_size**: System disk size (`20GiB`, `40GiB`, etc.)
- **additional_disks**: Array of additional storage disks

## AIStor License

**Important**: AIStor (Commercial MinIO) requires a valid SUBNET license.

1. Visit [SUBNET Portal](https://subnet.min.io) to obtain your license

1. Add the license to your configuration:

```yaml
aistor:
  license: "your-subnet-license-string-here"
```

1. Keep the license secure and do not commit it to version control

## Troubleshooting

### Common Issues

#### VM Creation Fails

```bash
# Check Lima installation
lima --version

# Check available resources
vm_stat | grep "Pages free"

# Verify Lima directory permissions
ls -la ~/.lima/
```

#### SSH Connection Issues

```bash
# Check VM status
limactl list

# Verify SSH config
limactl shell CLUSTER_NAME-node-name

# Regenerate inventory
./scripts/deploy-cluster.sh provision --config CONFIG_FILE --name your-cluster
```

#### Disk Mounting Problems

```bash
# Check disk status
limactl disk ls

# Verify disk creation
limactl disk ls

# Re-run disk mounting
./scripts/deploy-cluster.sh mount-disks --name your-cluster
```

#### Ansible Playbook Errors

```bash
# Check syntax
ansible-playbook --syntax-check ansible/playbooks/infrastructure/provision_vms.yml

# Run in dry-run mode
./scripts/deploy-cluster.sh --dry-run --config ansible/vars/dev-small.yml --name test

# Increase verbosity
ansible-playbook -vvv playbooks/infrastructure/provision_vms.yml
```

### Performance Tuning

**For Development**:

- Use `vars/dev-small.yml` configuration
- Allocate minimum resources (2GB RAM per node)
- Use smaller disk sizes

**For Production Testing**:

- Use `vars/prod-large.yml` configuration
- Ensure sufficient host resources (32GB+ RAM recommended)
- Monitor Lima VM resource usage

### Logs and Debugging

- Lima logs: `~/.lima/CLUSTER_NAME-NODE_NAME/ha.stderr.log`
- Ansible logs: `ansible.log` (if configured)
- VM console: `limactl shell CLUSTER_NAME-NODE_NAME`

## Development

### Project Structure

- **Makefile**: Main interface for all operations
- **CLAUDE.md**: Detailed development documentation
- **Playbooks**: Modular Ansible automation
- **Templates**: Jinja2 templates for configuration generation
- **Variables**: YAML-based cluster definitions

### Contributing

1. Fork the repository
1. Create a feature branch (`git checkout -b feature/amazing-feature`)
1. Make your changes
1. Test with multiple cluster configurations
1. Update documentation as needed
1. Submit a pull request

### Testing

```bash
# Syntax validation
ansible-playbook --syntax-check ansible/playbooks/infrastructure/provision_vms.yml

# Dry run (safe testing)
./scripts/deploy-cluster.sh --dry-run --config ansible/vars/dev-small.yml --name test

# Full test with cleanup
./scripts/deploy-cluster.sh --config ansible/vars/dev-small.yml --name test
./scripts/deploy-cluster.sh destroy --name test
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Lima](https://lima-vm.io/) for lightweight VM management
- [Ansible](https://ansible.com/) for infrastructure automation
- [MinIO](https://min.io/) for object storage
- [Kubernetes](https://kubernetes.io/) for container orchestration

## Support

- Issues: [GitHub Issues](https://github.com/your-username/lima_ansible/issues)
- Discussions: [GitHub Discussions](https://github.com/your-username/lima_ansible/discussions)
- Documentation: See `CLAUDE.md` for detailed development information

---

**Note**: This tool is designed for development and testing purposes. For production
deployments, consider using dedicated infrastructure providers and enterprise-grade
solutions.
