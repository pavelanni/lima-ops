#!/bin/bash

# Create Lima cluster with multiple VMs
# Based on pavelanni/lima_templates
#
# Usage: create_lima_cluster.sh -t <template> [-n nodes] [-d disks] [-p vm_prefix] [-s disk_prefix]

set -euo pipefail

# Default values
TEMPLATE_FILE=""
NUM_NODES=3
DISKS_PER_NODE=2
VM_PREFIX="minio"
DISK_PREFIX="minio"
FORCE=false

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
Usage: $0 -t <template> [-n nodes] [-d disks] [-p vm_prefix] [-s disk_prefix] [-f]

Create a Lima cluster with multiple VMs and attached disks.

OPTIONS:
    -t <template>       Lima template file (required)
    -n <nodes>         Number of nodes to create (default: 3)
    -d <disks>         Number of disks per node (default: 2)
    -p <vm_prefix>     VM name prefix (default: minio)
    -s <disk_prefix>   Disk name prefix (default: minio)
    -f                 Force creation without confirmation
    -h                 Show this help message

EXAMPLES:
    $0 -t rocky-server.yaml -n 4 -d 3
    $0 -t ../templates/rocky-server.yaml -n 2 -d 1 -p test -s storage
    $0 -t rocky-server.yaml -n 5 -d 2 -f

NOTES:
    - VM names will be: <vm_prefix>-node1, <vm_prefix>-node2, etc.
    - Disk names must exist as: <disk_prefix>-node1-disk1, etc.
    - Create disks first using create_disks.sh
    - Template file should be a valid Lima configuration
EOF
}

# Parse command line arguments
while getopts "t:n:d:p:s:fh" opt; do
    case $opt in
        t)
            TEMPLATE_FILE="$OPTARG"
            ;;
        n)
            NUM_NODES="$OPTARG"
            ;;
        d)
            DISKS_PER_NODE="$OPTARG"
            ;;
        p)
            VM_PREFIX="$OPTARG"
            ;;
        s)
            DISK_PREFIX="$OPTARG"
            ;;
        f)
            FORCE=true
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

# Validate required parameters
if [ -z "$TEMPLATE_FILE" ]; then
    error "Template file (-t) is required"
fi

# Validate template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    error "Template file not found: $TEMPLATE_FILE"
fi

# Validate numeric parameters
if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [ "$NUM_NODES" -lt 1 ]; then
    error "Number of nodes must be a positive integer"
fi

if ! [[ "$DISKS_PER_NODE" =~ ^[0-9]+$ ]] || [ "$DISKS_PER_NODE" -lt 0 ]; then
    error "Disks per node must be a non-negative integer"
fi

# Function to check if Lima is available
check_lima() {
    if ! command -v limactl >/dev/null 2>&1; then
        error "limactl not found. Please install Lima first."
    fi
    
    log "Lima version: $(limactl --version)"
}

# Function to check if VM already exists
vm_exists() {
    local vm_name="$1"
    limactl list | grep -q "^$vm_name\s" 2>/dev/null
}

# Function to check if disk exists
disk_exists() {
    local disk_name="$1"
    limactl disk ls | grep -q "^$disk_name\s" 2>/dev/null
}

# Function to get next available port
get_next_port() {
    local base_port=2222
    local port=$base_port
    
    while netstat -ln 2>/dev/null | grep -q ":$port "; do
        ((port++))
    done
    
    echo $port
}

# Function to validate required disks exist
validate_disks() {
    log "Validating required disks exist..."
    
    local missing_disks=0
    
    for node in $(seq 1 "$NUM_NODES"); do
        for disk in $(seq 1 "$DISKS_PER_NODE"); do
            local disk_name="${DISK_PREFIX}-node${node}-disk${disk}"
            
            if ! disk_exists "$disk_name"; then
                warn "Missing disk: $disk_name"
                ((missing_disks++))
            fi
        done
    done
    
    if [ "$missing_disks" -gt 0 ]; then
        error "$missing_disks required disks are missing. Create them first with create_disks.sh"
    fi
    
    log "All required disks are available"
}

# Function to create VM configuration with disks
create_vm_config() {
    local vm_name="$1"
    local node_number="$2"
    local ssh_port="$3"
    local temp_config="/tmp/${vm_name}.yaml"
    
    # Copy template file
    cp "$TEMPLATE_FILE" "$temp_config"
    
    # Add SSH port forwarding if not already present
    if ! grep -q "localPort:" "$temp_config"; then
        cat >> "$temp_config" << EOF

# SSH port forwarding
ssh:
  localPort: $ssh_port
  loadDotSSHPubKeys: true
EOF
    fi
    
    # Add disk configuration if disks are required
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        echo "" >> "$temp_config"
        echo "# Additional disks" >> "$temp_config"
        echo "additionalDisks:" >> "$temp_config"
        
        for disk in $(seq 1 "$DISKS_PER_NODE"); do
            local disk_name="${DISK_PREFIX}-node${node_number}-disk${disk}"
            cat >> "$temp_config" << EOF
- name: "$disk_name"
EOF
        done
    fi
    
    echo "$temp_config"
}

# Function to create a single VM
create_vm() {
    local vm_name="$1"
    local node_number="$2"
    
    if vm_exists "$vm_name"; then
        warn "VM '$vm_name' already exists, skipping"
        return 0
    fi
    
    local ssh_port=$(get_next_port)
    local temp_config=$(create_vm_config "$vm_name" "$node_number" "$ssh_port")
    
    log "Creating VM: $vm_name (SSH port: $ssh_port)"
    
    if limactl create "$temp_config" --name "$vm_name"; then
        log "Successfully created VM: $vm_name"
        
        # Clean up temp config
        rm -f "$temp_config"
        
        return 0
    else
        error "Failed to create VM: $vm_name"
    fi
}

# Function to start VM
start_vm() {
    local vm_name="$1"
    
    log "Starting VM: $vm_name"
    
    if limactl start "$vm_name"; then
        log "Successfully started VM: $vm_name"
    else
        warn "Failed to start VM: $vm_name"
    fi
}

# Function to show confirmation
show_confirmation() {
    info "Cluster creation plan:"
    echo "  Template file: $TEMPLATE_FILE"
    echo "  Number of nodes: $NUM_NODES"
    echo "  Disks per node: $DISKS_PER_NODE"
    echo "  VM prefix: $VM_PREFIX"
    echo "  Disk prefix: $DISK_PREFIX"
    echo "  VMs to create:"
    
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        local status=""
        
        if vm_exists "$vm_name"; then
            status=" ${YELLOW}(exists - will skip)${NC}"
        else
            status=" ${GREEN}(will create)${NC}"
        fi
        
        echo -e "    - $vm_name$status"
    done
    
    echo ""
    
    if [ "$FORCE" = false ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled"
            exit 0
        fi
    fi
}

# Main function
main() {
    log "Starting Lima cluster creation..."
    
    # Check prerequisites
    check_lima
    
    # Validate disks exist
    if [ "$DISKS_PER_NODE" -gt 0 ]; then
        validate_disks
    fi
    
    # Show current VMs
    log "Current Lima VMs:"
    limactl list 2>/dev/null || warn "No existing VMs found"
    echo
    
    # Show confirmation
    show_confirmation
    
    # Create VMs
    local created_count=0
    local skipped_count=0
    
    for node in $(seq 1 "$NUM_NODES"); do
        local vm_name="${VM_PREFIX}-node${node}"
        
        if vm_exists "$vm_name"; then
            ((skipped_count++))
        else
            create_vm "$vm_name" "$node"
            start_vm "$vm_name"
            ((created_count++))
        fi
    done
    
    # Summary
    log "Cluster creation completed!"
    info "Created: $created_count VMs"
    info "Skipped: $skipped_count VMs"
    
    log "Cluster status:"
    limactl list | grep -E "^(NAME|${VM_PREFIX})" || warn "No cluster VMs found"
}

# Run main function
main "$@"