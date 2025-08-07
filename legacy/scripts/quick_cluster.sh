#!/bin/bash

# Quick MinIO cluster setup script
# Combines disk creation, VM provisioning, and user setup
# Based on pavelanni/lima_templates
#
# Usage: quick_cluster.sh [-n nodes] [-d disks] [-s size] [-p prefix]

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"

# Default values
NUM_NODES=3
DISKS_PER_NODE=2
DISK_SIZE="20GiB"
CLUSTER_PREFIX="minio"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [-n nodes] [-d disks] [-s size] [-p prefix]

Quick MinIO cluster setup - creates disks, VMs, and configures users.

OPTIONS:
    -n <nodes>     Number of nodes in cluster (default: 3)
    -d <disks>     Number of disks per node (default: 2)
    -s <size>      Size of each disk (default: 20GiB)
    -p <prefix>    Cluster name prefix (default: minio)
    -h             Show this help message

EXAMPLES:
    $0                          # 3-node cluster, 2x20GiB disks per node
    $0 -n 4 -d 3 -s 50GiB      # 4-node cluster, 3x50GiB disks per node
    $0 -n 2 -s 10GiB -p test   # 2-node test cluster

WHAT THIS SCRIPT DOES:
    1. Creates Lima disks for storage
    2. Provisions Rocky Linux VMs
    3. Sets up MinIO users and groups
    4. Prepares cluster for MinIO installation

NEXT STEPS AFTER COMPLETION:
    1. SSH into VMs: limactl shell <vm-name>
    2. Mount disks: sudo /path/to/mount_disks.sh
    3. Install and configure MinIO
EOF
}

# Parse command line arguments
while getopts "n:d:s:p:h" opt; do
    case $opt in
        n)
            NUM_NODES="$OPTARG"
            ;;
        d)
            DISKS_PER_NODE="$OPTARG"
            ;;
        s)
            DISK_SIZE="$OPTARG"
            ;;
        p)
            CLUSTER_PREFIX="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            error "Invalid option: -$OPTARG"
            ;;
        :)
            error "Option -$OPTARG requires an argument"
            ;;
    esac
done

# Validate parameters
if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [ "$NUM_NODES" -lt 1 ]; then
    error "Number of nodes must be a positive integer"
fi

if ! [[ "$DISKS_PER_NODE" =~ ^[0-9]+$ ]] || [ "$DISKS_PER_NODE" -lt 0 ]; then
    error "Disks per node must be a non-negative integer"
fi

# Function to show setup plan
show_setup_plan() {
    info "Quick MinIO Cluster Setup Plan:"
    echo "  Cluster prefix: $CLUSTER_PREFIX"
    echo "  Number of nodes: $NUM_NODES"
    echo "  Disks per node: $DISKS_PER_NODE"
    echo "  Disk size: $DISK_SIZE"
    echo ""
    echo "This will create:"
    
    local total_disks=$((NUM_NODES * DISKS_PER_NODE))
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        echo "  - $total_disks Lima disks (${DISK_SIZE} each)"
    fi
    echo "  - $NUM_NODES Rocky Linux VMs"
    echo "  - MinIO users and groups on all nodes"
    echo ""
    
    read -p "Continue with cluster creation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled"
        exit 0
    fi
}

# Function to create disks for all nodes
create_all_disks() {
    if [ "$DISKS_PER_NODE" -eq 0 ]; then
        log "Skipping disk creation (no disks requested)"
        return 0
    fi
    
    log "Step 1: Creating Lima disks..."
    
    for node in $(seq 1 "$NUM_NODES"); do
        for disk in $(seq 1 "$DISKS_PER_NODE"); do
            local disk_name="${CLUSTER_PREFIX}-node${node}-disk${disk}"
            
            if "$SCRIPT_DIR/create_disks.sh" -n 1 -s "$DISK_SIZE" -p "$disk_name" -f; then
                log "Created disk: $disk_name"
            else
                warn "Failed to create or disk already exists: $disk_name"
            fi
        done
    done
    
    log "Disk creation completed"
}

# Function to provision VMs
provision_cluster() {
    log "Step 2: Provisioning Lima VMs..."
    
    local template_file="$TEMPLATE_DIR/rocky-server.yaml"
    
    if [ ! -f "$template_file" ]; then
        error "Template file not found: $template_file"
    fi
    
    if "$SCRIPT_DIR/create_lima_cluster.sh" -t "$template_file" -n "$NUM_NODES" -d "$DISKS_PER_NODE" -p "$CLUSTER_PREFIX" -s "$CLUSTER_PREFIX" -f; then
        log "VM provisioning completed"
    else
        error "Failed to provision VMs"
    fi
}

# Function to setup MinIO users
setup_users() {
    log "Step 3: Setting up MinIO users..."
    
    # Wait a bit for VMs to fully start
    log "Waiting for VMs to be ready..."
    sleep 10
    
    if "$SCRIPT_DIR/setup_minio_users.sh" -n "$NUM_NODES" -p "$CLUSTER_PREFIX"; then
        log "MinIO user setup completed"
    else
        warn "MinIO user setup had issues (check logs above)"
    fi
}

# Function to show completion summary
show_completion() {
    log "🎉 Quick MinIO cluster setup completed!"
    echo ""
    info "Cluster Details:"
    echo "  Cluster name: $CLUSTER_PREFIX"
    echo "  Nodes: $NUM_NODES"
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        echo "  Storage disks: $DISKS_PER_NODE per node (${DISK_SIZE} each)"
    fi
    echo ""
    
    log "Cluster Status:"
    limactl list | grep -E "^(NAME|${CLUSTER_PREFIX})" || warn "No cluster VMs found in status"
    echo ""
    
    log "Next Steps:"
    echo "1. SSH into a node:"
    echo "   limactl shell ${CLUSTER_PREFIX}-node1"
    echo ""
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        echo "2. Mount storage disks (run on each node as root):"
        echo "   sudo $SCRIPT_DIR/mount_disks.sh"
        echo ""
    fi
    echo "3. Install MinIO (example):"
    echo "   # Download and install MinIO binary"
    echo "   # Configure distributed MinIO across nodes"
    echo "   # Start MinIO services"
    echo ""
    
    log "Management Commands:"
    echo "  View VMs:      limactl list"
    echo "  Stop cluster:  $SCRIPT_DIR/delete_lima_cluster.sh -p $CLUSTER_PREFIX"
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        echo "  View disks:    limactl disk ls"
    fi
}

# Main function
main() {
    log "Starting quick MinIO cluster setup..."
    
    # Show setup plan and get confirmation
    show_setup_plan
    
    # Execute setup steps
    create_all_disks
    provision_cluster
    setup_users
    
    # Show completion summary
    show_completion
}

# Run main function
main "$@"