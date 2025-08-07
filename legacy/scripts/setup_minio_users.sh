#!/bin/bash

# Setup MinIO users and groups on Lima cluster nodes
# Based on pavelanni/lima_templates
#
# Usage: setup_minio_users.sh [-n nodes] [-p prefix] [-u uid] [-g gid]

set -euo pipefail

# Default values
NUM_NODES=3
VM_PREFIX="minio"
MINIO_UID=1001
MINIO_GID=1001
MINIO_USER="minio-user"
MINIO_GROUP="minio-user"

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
Usage: $0 [-n nodes] [-p prefix] [-u uid] [-g gid]

Setup MinIO user and group on Lima cluster nodes.

OPTIONS:
    -n <nodes>     Number of nodes in cluster (default: 3)
    -p <prefix>    VM name prefix (default: minio)
    -u <uid>       MinIO user ID (default: 1001)
    -g <gid>       MinIO group ID (default: 1001)
    -h             Show this help message

EXAMPLES:
    $0                           # Setup on 3 nodes with default settings
    $0 -n 4 -p storage          # Setup on 4 nodes with 'storage' prefix
    $0 -n 5 -u 2001 -g 2001     # Setup with custom UID/GID

NOTES:
    - User name will be: $MINIO_USER
    - Group name will be: $MINIO_GROUP
    - VMs must be running before executing this script
    - Script will create user/group on each node: <prefix>-node1, <prefix>-node2, etc.
EOF
}

# Parse command line arguments
while getopts "n:p:u:g:h" opt; do
    case $opt in
        n)
            NUM_NODES="$OPTARG"
            ;;
        p)
            VM_PREFIX="$OPTARG"
            ;;
        u)
            MINIO_UID="$OPTARG"
            ;;
        g)
            MINIO_GID="$OPTARG"
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

# Validate numeric parameters
if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [ "$NUM_NODES" -lt 1 ]; then
    error "Number of nodes must be a positive integer"
fi

if ! [[ "$MINIO_UID" =~ ^[0-9]+$ ]] || [ "$MINIO_UID" -lt 1 ]; then
    error "MinIO UID must be a positive integer"
fi

if ! [[ "$MINIO_GID" =~ ^[0-9]+$ ]] || [ "$MINIO_GID" -lt 1 ]; then
    error "MinIO GID must be a positive integer"
fi

# Function to check if Lima is available
check_lima() {
    if ! command -v limactl >/dev/null 2>&1; then
        error "limactl not found. Please install Lima first."
    fi
    
    log "Lima version: $(limactl --version)"
}

# Function to check if VM is running
vm_is_running() {
    local vm_name="$1"
    limactl list | grep "^$vm_name\s" | grep -q "Running" 2>/dev/null
}

# Function to validate all VMs are running
validate_vms() {
    log "Validating cluster VMs are running..."
    
    local missing_vms=0
    local stopped_vms=0
    
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        
        if ! limactl list | grep -q "^$vm_name\s" 2>/dev/null; then
            warn "VM not found: $vm_name"
            ((missing_vms++))
        elif ! vm_is_running "$vm_name"; then
            warn "VM not running: $vm_name"
            ((stopped_vms++))
        fi
    done
    
    if [ "$missing_vms" -gt 0 ]; then
        error "$missing_vms VMs are missing. Create cluster first with create_lima_cluster.sh"
    fi
    
    if [ "$stopped_vms" -gt 0 ]; then
        error "$stopped_vms VMs are stopped. Start them with 'limactl start <vm-name>'"
    fi
    
    log "All cluster VMs are running"
}

# Function to setup user on a single VM
setup_user_on_vm() {
    local vm_name="$1"
    local node_number="$2"
    
    log "Setting up MinIO user on VM: $vm_name"
    
    # Create group first
    if limactl shell "$vm_name" sudo groupadd -g "$MINIO_GID" "$MINIO_GROUP" 2>/dev/null; then
        log "Created group '$MINIO_GROUP' (GID: $MINIO_GID) on $vm_name"
    else
        warn "Group '$MINIO_GROUP' may already exist on $vm_name"
    fi
    
    # Create user
    if limactl shell "$vm_name" sudo useradd -u "$MINIO_UID" -g "$MINIO_GID" -r -s /bin/bash -d /home/"$MINIO_USER" -c "MinIO User" "$MINIO_USER" 2>/dev/null; then
        log "Created user '$MINIO_USER' (UID: $MINIO_UID) on $vm_name"
    else
        warn "User '$MINIO_USER' may already exist on $vm_name"
    fi
    
    # Create home directory
    limactl shell "$vm_name" sudo mkdir -p /home/"$MINIO_USER"
    limactl shell "$vm_name" sudo chown "$MINIO_USER":"$MINIO_GROUP" /home/"$MINIO_USER"
    
    # Set ownership of MinIO data directories if they exist
    local data_dirs=$(limactl shell "$vm_name" find /mnt -name "minio*" -type d 2>/dev/null || true)
    if [ -n "$data_dirs" ]; then
        log "Setting ownership of MinIO data directories on $vm_name"
        echo "$data_dirs" | while read -r dir; do
            if [ -n "$dir" ]; then
                limactl shell "$vm_name" sudo chown -R "$MINIO_USER":"$MINIO_GROUP" "$dir" 2>/dev/null || warn "Could not set ownership for $dir"
            fi
        done
    fi
    
    # Verify user was created
    if limactl shell "$vm_name" id "$MINIO_USER" >/dev/null 2>&1; then
        log "Successfully verified user '$MINIO_USER' on $vm_name"
        
        # Show user info
        local user_info=$(limactl shell "$vm_name" id "$MINIO_USER" 2>/dev/null || echo "Failed to get user info")
        info "User info on $vm_name: $user_info"
    else
        error "Failed to create user '$MINIO_USER' on $vm_name"
    fi
}

# Function to show setup summary
show_summary() {
    info "MinIO User Setup Plan:"
    echo "  Number of nodes: $NUM_NODES"
    echo "  VM prefix: $VM_PREFIX"
    echo "  MinIO user: $MINIO_USER"
    echo "  MinIO group: $MINIO_GROUP"
    echo "  User ID: $MINIO_UID"
    echo "  Group ID: $MINIO_GID"
    echo "  Target VMs:"
    
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        echo "    - $vm_name"
    done
    
    echo ""
}

# Main function
main() {
    log "Starting MinIO user setup..."
    
    # Check prerequisites
    check_lima
    
    # Show setup summary
    show_summary
    
    # Validate VMs are running
    validate_vms
    
    # Setup users on each VM
    local success_count=0
    local failed_count=0
    
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        
        if setup_user_on_vm "$vm_name" "$node"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Summary
    log "MinIO user setup completed!"
    info "Successful: $success_count nodes"
    if [ "$failed_count" -gt 0 ]; then
        warn "Failed: $failed_count nodes"
    fi
    
    log "User setup verification:"
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        local user_check=$(limactl shell "$vm_name" id "$MINIO_USER" 2>/dev/null || echo "FAILED")
        echo "  $vm_name: $user_check"
    done
}

# Run main function
main "$@"