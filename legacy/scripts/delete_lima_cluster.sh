#!/bin/bash

# Delete Lima cluster VMs
# Based on pavelanni/lima_templates
#
# Usage: delete_lima_cluster.sh [-p prefix] [-f]

set -euo pipefail

# Default values
VM_PREFIX="minio"
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
Usage: $0 [-p prefix] [-f]

Delete Lima cluster VMs with specified prefix.

OPTIONS:
    -p <prefix>    VM name prefix to delete (default: minio)
    -f             Force deletion without confirmation
    -h             Show this help message

EXAMPLES:
    $0                    # Delete all VMs with 'minio' prefix
    $0 -p test           # Delete all VMs with 'test' prefix
    $0 -p storage -f     # Force delete all VMs with 'storage' prefix

NOTES:
    - This will stop and delete all VMs matching: <prefix>-*
    - VMs are stopped before deletion
    - Use with caution - deletion is irreversible
    - Associated disks are NOT deleted automatically
EOF
}

# Parse command line arguments
while getopts "p:fh" opt; do
    case $opt in
        p)
            VM_PREFIX="$OPTARG"
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

# Function to check if Lima is available
check_lima() {
    if ! command -v limactl >/dev/null 2>&1; then
        error "limactl not found. Please install Lima first."
    fi
    
    log "Lima version: $(limactl --version)"
}

# Function to find VMs with prefix
find_cluster_vms() {
    local vms=$(limactl list -q | grep "^${VM_PREFIX}-" || true)
    echo "$vms"
}

# Function to stop VM
stop_vm() {
    local vm_name="$1"
    
    log "Stopping VM: $vm_name"
    
    if limactl stop "$vm_name" 2>/dev/null; then
        log "Successfully stopped VM: $vm_name"
    else
        warn "Failed to stop VM: $vm_name (may already be stopped)"
    fi
}

# Function to delete VM
delete_vm() {
    local vm_name="$1"
    
    log "Deleting VM: $vm_name"
    
    if limactl delete "$vm_name" 2>/dev/null; then
        log "Successfully deleted VM: $vm_name"
        return 0
    else
        warn "Failed to delete VM: $vm_name"
        return 1
    fi
}

# Function to show confirmation
show_confirmation() {
    local vms="$1"
    
    if [ -z "$vms" ]; then
        info "No VMs found with prefix: $VM_PREFIX"
        exit 0
    fi
    
    info "VMs to be deleted (prefix: $VM_PREFIX):"
    echo "$vms" | while read -r vm; do
        echo "  - $vm"
    done
    
    echo ""
    warn "This action is irreversible!"
    
    if [ "$FORCE" = false ]; then
        read -p "Continue with deletion? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled"
            exit 0
        fi
    fi
}

# Main function
main() {
    log "Starting Lima cluster deletion..."
    
    # Check prerequisites
    check_lima
    
    # Find cluster VMs
    local cluster_vms=$(find_cluster_vms)
    
    # Show current VMs
    log "Current Lima VMs:"
    limactl list 2>/dev/null || warn "No VMs found"
    echo
    
    # Show confirmation
    show_confirmation "$cluster_vms"
    
    # Delete VMs
    local deleted_count=0
    local failed_count=0
    
    echo "$cluster_vms" | while read -r vm_name; do
        if [ -n "$vm_name" ]; then
            # Stop VM first
            stop_vm "$vm_name"
            sleep 2
            
            # Delete VM
            if delete_vm "$vm_name"; then
                ((deleted_count++))
            else
                ((failed_count++))
            fi
        fi
    done
    
    # Summary
    log "Cluster deletion completed!"
    
    # Check if any VMs remain
    local remaining_vms=$(find_cluster_vms)
    if [ -z "$remaining_vms" ]; then
        log "All cluster VMs successfully deleted"
    else
        warn "Some VMs may still exist:"
        echo "$remaining_vms"
    fi
    
    log "Current VM status:"
    limactl list 2>/dev/null || log "No VMs remaining"
    
    info "Note: Associated disks were NOT deleted automatically"
    info "Use 'limactl disk ls' to see remaining disks"
    info "Use delete_disks.sh to clean up disks if needed"
}

# Run main function
main "$@"