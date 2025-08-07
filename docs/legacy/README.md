# Legacy Shell Script Documentation

## Overview

The legacy approach provides battle-tested shell scripts originally developed for production MinIO deployments. These scripts offer a simpler, more direct approach to Lima VM management compared to the Ansible automation.

## When to Use Legacy Scripts

**✅ Choose Legacy When:**
- Quick prototyping or testing
- Simple cluster requirements
- Familiar with shell scripting
- Want minimal dependencies
- Need proven, battle-tested automation

**❌ Use Ansible Instead When:**
- Complex multi-environment deployments
- Infrastructure-as-code requirements
- Team collaboration and standardization
- Advanced configuration management

## Quick Start

### Complete Cluster Setup (Recommended)

```bash
# Create a 3-node MinIO cluster with 2x20GiB disks per node
./legacy/scripts/quick_cluster.sh -n 3 -d 2 -s 20GiB

# Create a 4-node cluster with 3x50GiB disks per node  
./legacy/scripts/quick_cluster.sh -n 4 -d 3 -s 50GiB -p storage

# Test cluster with minimal resources
./legacy/scripts/quick_cluster.sh -n 2 -d 1 -s 10GiB -p test
```

The `quick_cluster.sh` script will:
1. Create all required Lima disks
2. Provision Rocky Linux VMs
3. Set up MinIO users and groups
4. Prepare cluster for MinIO installation

### Step-by-Step Approach

If you prefer manual control over each step:

#### 1. Create Storage Disks

```bash
# Create 4 disks of 50GiB each
./legacy/scripts/create_disks.sh -n 4 -s 50GiB -p minio

# Create disks with custom prefix
./legacy/scripts/create_disks.sh -n 6 -s 100GB -p storage-cluster
```

#### 2. Provision VMs

```bash
# Create 3-node cluster with 2 disks per node
./legacy/scripts/create_lima_cluster.sh -t legacy/templates/rocky-server.yaml -n 3 -d 2

# Create cluster with custom naming
./legacy/scripts/create_lima_cluster.sh -t legacy/templates/rocky-server.yaml -n 4 -d 3 -p storage -s storage-cluster
```

#### 3. Setup MinIO Users

```bash
# Setup MinIO users on all nodes
./legacy/scripts/setup_minio_users.sh -n 3

# Setup users with custom IDs
./legacy/scripts/setup_minio_users.sh -n 4 -p storage -u 2001 -g 2001
```

#### 4. Mount Disks (Run Inside Each VM)

```bash
# SSH into each VM
limactl shell minio-node1

# Mount disks (as root)
sudo /path/to/mount_disks.sh
```

## Templates

### Rocky Linux Server (`rocky-server.yaml`)

**Purpose**: Standard MinIO cluster nodes  
**Resources**: 2 CPUs, 4GiB RAM, 20GB disk  
**Includes**: Basic system tools (net-tools, vim, bc, lsof)

**Usage**:
```bash
# Direct Lima usage
limactl create legacy/templates/rocky-server.yaml --name my-server

# With cluster scripts
./legacy/scripts/create_lima_cluster.sh -t legacy/templates/rocky-server.yaml -n 3
```

### Rocky Linux Client (`rocky-client.yaml`)

**Purpose**: MinIO client and testing  
**Resources**: 2 CPUs, 4GiB RAM, 20GB disk  
**Includes**: MinIO Client (mc), Warp performance testing tool

**Usage**:
```bash
# Create client VM for cluster management
limactl create legacy/templates/rocky-client.yaml --name minio-client
limactl start minio-client
```

## Script Reference

### Disk Management Scripts

#### `create_disks.sh`
Creates multiple Lima disks with specified size and naming.

```bash
./legacy/scripts/create_disks.sh -n <number> -s <size> [-p prefix] [-f]

# Examples
./legacy/scripts/create_disks.sh -n 4 -s 50GiB
./legacy/scripts/create_disks.sh -n 2 -s 100GB -p test -f
```

#### `mount_disks.sh`
Mounts and formats disks for MinIO storage (run inside VMs as root).

**Features:**
- Detects available disks automatically
- Excludes system disk (vda) and Lima metadata (cidata)
- Creates XFS filesystems with GPT partition tables
- UUID-based /etc/fstab entries
- Creates MinIO data directories
- Sets proper ownership if minio-user exists

```bash
# Run inside VM as root
sudo ./mount_disks.sh
```

### Cluster Management Scripts

#### `create_lima_cluster.sh`
Creates multiple Lima VMs with attached disks.

```bash
./legacy/scripts/create_lima_cluster.sh -t <template> [-n nodes] [-d disks] [-p vm_prefix] [-s disk_prefix]

# Examples
./legacy/scripts/create_lima_cluster.sh -t legacy/templates/rocky-server.yaml -n 4 -d 3
./legacy/scripts/create_lima_cluster.sh -t rocky-server.yaml -n 2 -p test -s storage
```

#### `delete_lima_cluster.sh`
Deletes all VMs with specified prefix.

```bash
./legacy/scripts/delete_lima_cluster.sh [-p prefix] [-f]

# Examples  
./legacy/scripts/delete_lima_cluster.sh -p minio
./legacy/scripts/delete_lima_cluster.sh -p test -f
```

### MinIO Setup Scripts

#### `setup_minio_users.sh`
Creates MinIO users and groups on all cluster nodes.

```bash
./legacy/scripts/setup_minio_users.sh [-n nodes] [-p prefix] [-u uid] [-g gid]

# Examples
./legacy/scripts/setup_minio_users.sh -n 4
./legacy/scripts/setup_minio_users.sh -n 3 -p storage -u 2001 -g 2001
```

## Typical Workflows

### Development Cluster

```bash
# Quick 2-node cluster for testing
./legacy/scripts/quick_cluster.sh -n 2 -d 1 -s 10GiB -p dev

# Access the cluster
limactl list
limactl shell dev-node1
```

### Production-like Cluster

```bash
# 4-node cluster with 3 large disks per node
./legacy/scripts/quick_cluster.sh -n 4 -d 3 -s 100GiB -p prod

# Verify setup
limactl list | grep prod
limactl disk ls | grep prod
```

### Testing Different Configurations

```bash
# Test cluster with minimal resources
./legacy/scripts/quick_cluster.sh -n 2 -d 1 -s 5GiB -p test1

# Storage-focused cluster
./legacy/scripts/quick_cluster.sh -n 3 -d 4 -s 50GiB -p storage

# Clean up when done
./legacy/scripts/delete_lima_cluster.sh -p test1 -f
./legacy/scripts/delete_lima_cluster.sh -p storage -f
```

## Troubleshooting

### Common Issues

**VMs won't start:**
```bash
# Check Lima status
limactl list

# Check logs
limactl start vm-name --log-level=debug

# Check template syntax
lima validate legacy/templates/rocky-server.yaml
```

**Disk creation fails:**
```bash
# Check existing disks
limactl disk ls

# Check disk space on host
df -h

# Clean up old disks if needed
limactl disk delete old-disk-name
```

**Mount script fails in VM:**
```bash
# Check available disks in VM
sudo lsblk

# Check if disks are attached
sudo fdisk -l

# Manually mount if needed
sudo mkdir /mnt/minio1
sudo mount /dev/vdb1 /mnt/minio1
```

### Performance Tips

**For Development:**
- Use smaller disk sizes (5-10GiB)
- Reduce VM resources in template
- Use fewer nodes (2-3)

**For Production Testing:**
- Use realistic disk sizes (50-100GiB+)
- Don't overcommit host resources
- Monitor host system performance

## Migration to Ansible

When you're ready to move to the Ansible approach:

1. **Export configurations**: Document your current cluster specifications
2. **Create Ansible vars**: Convert to `ansible/vars/` configuration files
3. **Test Ansible approach**: Use `make ansible-help` for guidance
4. **Gradual transition**: Run both approaches in parallel initially

See [Migration Guide](migration.md) for detailed steps.

## Contributing

Legacy scripts follow these conventions:
- Bash with strict error handling (`set -euo pipefail`)
- Color-coded output for readability
- Comprehensive help messages (`-h` flag)
- Input validation and error checking
- Descriptive logging throughout execution

When modifying scripts, maintain backward compatibility and update this documentation.