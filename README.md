# Lima-Ops: Comprehensive Lima VM Management

A complete toolkit for provisioning and managing clusters using Lima VMs on macOS. Provides both modern Ansible automation and proven shell script approaches for maximum flexibility. Supports Kubernetes-based deployments and bare-metal MinIO clusters with enterprise-grade storage solutions.

## Overview

This project provides a comprehensive toolkit for creating development and production clusters on your local machine using Lima VMs. It offers two complementary approaches:

### **🚀 Modern Approach (Recommended)**
- **Ansible Automation**: Infrastructure-as-code with declarative configuration
- **Multi-cluster Management**: Template-based cluster configurations
- **Enterprise Integration**: AIStor (Commercial MinIO) support

### **⚡ Legacy Approach (Battle-tested)**
- **Shell Scripts**: Proven automation scripts from production use
- **Lima Templates**: Ready-to-use VM configurations
- **Quick Deployment**: Fast cluster provisioning for immediate needs

### Supported Deployments

- **Kubernetes Clusters**: Container orchestration with AIStor (Commercial MinIO) integration
- **Bare-metal MinIO**: High-performance object storage clusters for dedicated storage workloads
- **Mixed Environments**: Combine approaches based on specific needs

## Quick Start

### Prerequisites

- macOS with Apple Silicon or Intel
- [Lima](https://lima-vm.io/) installed (`brew install lima`)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) installed (`brew install ansible`)
- At least 8GB RAM and 50GB free disk space (for development clusters)

### Installation

1. Clone this repository:
```bash
git clone https://github.com/your-username/lima_ansible.git
cd lima_ansible
```

2. Verify prerequisites:
```bash
lima --version
ansible --version
```

### Deploy Your First Cluster

#### **Modern Ansible Approach** (Recommended)
```bash
# Small development cluster (1 control-plane + 1 worker)
make ansible full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev

# Check cluster status
make ansible status

# SSH into a node
limactl shell dev-control-plane-01
```

#### **Legacy Shell Script Approach** (Coming Soon)
```bash
# Quick MinIO cluster
make legacy provision CLUSTER_SIZE=3

# Check status
make legacy status
```

#### **Choose Your Approach**
```bash
# See all options
make help

# Ansible automation help
make ansible-help

# Legacy scripts help (when available)
make legacy-help
```

## Configuration Options

The project includes several pre-configured cluster templates:

| Config File | Description | Nodes | Resources |
|-------------|-------------|--------|-----------|
| `vars/dev-small.yml` | Small development cluster | 1 control + 1 worker | 2 CPU, 2GB RAM each |
| `vars/prod-large.yml` | Large production cluster | 3 control + 4 workers | 4 CPU, 8GB RAM each |
| `vars/baremetal-simple.yml` | Simple MinIO storage | 4 storage nodes | 2 CPU, 4GB RAM each |
| `vars/cluster_config.yml` | Default Kubernetes | 1 control + 2 workers | Variable resources |
| `vars/baremetal_config.yml` | Default MinIO | Variable nodes | Variable resources |

## Usage

### Complete Workflows

```bash
# Development cluster
make full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev

# Production cluster  
make full-setup CONFIG_FILE=vars/prod-large.yml CLUSTER_NAME=production

# Bare-metal storage cluster
make full-setup CONFIG_FILE=vars/baremetal-simple.yml CLUSTER_NAME=storage
```

### Step-by-step Deployment

```bash
# 1. Validate configuration
make validate CONFIG_FILE=vars/dev-small.yml

# 2. Create storage disks
make create-disks CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev

# 3. Provision VMs
make provision CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=dev

# 4. Configure VMs
make configure CLUSTER_NAME=dev

# 5. Mount storage disks
make mount-disks CLUSTER_NAME=dev

# 6. Deploy applications
make deploy CLUSTER_NAME=dev
```

### Management Commands

```bash
make status              # Show VM status
make show-config         # Show current configuration  
make list-disks         # List Lima disks
make destroy CLUSTER_NAME=dev  # Destroy cluster
make help               # Show all available commands
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
2. **Configuration Phase**: OS configuration, disk mounting, package installation  
3. **Application Phase**: Kubernetes or MinIO deployment and configuration

### Directory Structure

```
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
├── inventory/           # Generated inventory files (shared)
└── README.md           # This file
```

## Customization

### Creating Custom Configurations

1. Copy an existing configuration:
```bash
cp vars/dev-small.yml vars/my-custom.yml
```

2. Edit the configuration:
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

3. Deploy with your custom configuration:
```bash
make full-setup CONFIG_FILE=vars/my-custom.yml CLUSTER_NAME=custom
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
2. Add the license to your configuration:
```yaml
aistor:
  license: "your-subnet-license-string-here"
```
3. Keep the license secure and do not commit it to version control

## Troubleshooting

### Common Issues

**VM Creation Fails**
```bash
# Check Lima installation
lima --version

# Check available resources
vm_stat | grep "Pages free"

# Verify Lima directory permissions
ls -la ~/.lima/
```

**SSH Connection Issues**
```bash
# Check VM status
limactl list

# Verify SSH config
limactl shell CLUSTER_NAME-node-name

# Regenerate inventory
make inventory CLUSTER_NAME=your-cluster
```

**Disk Mounting Problems**
```bash
# Check disk status
make list-disks

# Verify disk creation
limactl disk ls

# Re-run disk mounting
make mount-disks CLUSTER_NAME=your-cluster
```

**Ansible Playbook Errors**
```bash
# Check syntax
make syntax-check

# Run in dry-run mode
make dry-run CONFIG_FILE=vars/dev-small.yml

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
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test with multiple cluster configurations
5. Update documentation as needed
6. Submit a pull request

### Testing

```bash
# Syntax validation
make syntax-check

# Dry run (safe testing)
make dry-run CONFIG_FILE=vars/dev-small.yml

# Full test with cleanup
make full-setup CONFIG_FILE=vars/dev-small.yml CLUSTER_NAME=test
make destroy CLUSTER_NAME=test
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

**Note**: This tool is designed for development and testing purposes. For production deployments, consider using dedicated infrastructure providers and enterprise-grade solutions.