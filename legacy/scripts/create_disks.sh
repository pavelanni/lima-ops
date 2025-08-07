#!/bin/bash

# Create multiple Lima disks for cluster storage
# Based on pavelanni/lima_templates
#
# Usage: create_disks.sh -n <number> -s <size> [-p prefix] [-f]

set -euo pipefail

# Default values
NUM_DISKS=""
DISK_SIZE=""
PREFIX="minio"
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
Usage: $0 -n <number> -s <size> [-p prefix] [-f]

Create multiple Lima disks for cluster storage.

OPTIONS:
    -n <number>     Number of disks to create (required)
    -s <size>       Size of each disk (e.g., 10GiB, 100GB) (required)  
    -p <prefix>     Disk name prefix (default: minio)
    -f              Force creation without confirmation
    -h              Show this help message

EXAMPLES:
    $0 -n 4 -s 50GiB
    $0 -n 3 -s 100GB -p storage -f
    $0 -n 2 -s 20GiB -p test

NOTES:
    - Disk names will be: <prefix>-disk1, <prefix>-disk2, etc.
    - Existing disks with the same name will be skipped
    - Use 'limactl disk ls' to see existing disks
EOF
}

# Parse command line arguments
while getopts "n:s:p:fh" opt; do
    case $opt in
        n)
            NUM_DISKS="$OPTARG"
            ;;
        s)
            DISK_SIZE="$OPTARG"
            ;;
        p)
            PREFIX="$OPTARG"
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
if [ -z "$NUM_DISKS" ] || [ -z "$DISK_SIZE" ]; then
    error "Both -n (number) and -s (size) are required"
fi

# Validate number of disks
if ! [[ "$NUM_DISKS" =~ ^[0-9]+$ ]] || [ "$NUM_DISKS" -lt 1 ]; then
    error "Number of disks must be a positive integer"
fi

# Validate disk size format
if ! [[ "$DISK_SIZE" =~ ^[0-9]+[GM]i?B?$ ]]; then
    error "Invalid disk size format. Use formats like: 10GiB, 100GB, 50MiB"
fi

# Function to check if Lima is available
check_lima() {
    if ! command -v limactl >/dev/null 2>&1; then
        error "limactl not found. Please install Lima first."
    fi
    
    log "Lima version: $(limactl --version)"
}

# Function to check if disk already exists
disk_exists() {
    local disk_name="$1"
    limactl disk ls | grep -q "^$disk_name\s" 2>/dev/null
}

# Function to create a single disk
create_disk() {
    local disk_name="$1"
    local size="$2"
    
    if disk_exists "$disk_name"; then
        warn "Disk '$disk_name' already exists, skipping"
        return 0
    fi
    
    log "Creating disk: $disk_name (size: $size)"
    
    if limactl disk create "$disk_name" --size "$size" --format raw; then
        log "Successfully created disk: $disk_name"
        return 0
    else
        error "Failed to create disk: $disk_name"
    fi
}

# Function to show confirmation
show_confirmation() {
    info "Disk creation plan:"
    echo "  Number of disks: $NUM_DISKS"
    echo "  Disk size: $DISK_SIZE"
    echo "  Disk prefix: $PREFIX"
    echo "  Disk names: "
    
    for i in $(seq 1 "$NUM_DISKS"); do
        local disk_name="${PREFIX}-disk${i}"
        local status=""
        
        if disk_exists "$disk_name"; then
            status=" ${YELLOW}(exists - will skip)${NC}"
        else
            status=" ${GREEN}(will create)${NC}"
        fi
        
        echo -e "    - $disk_name$status"
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
    log "Starting disk creation process..."
    
    # Check prerequisites
    check_lima
    
    # Show current disks
    log "Current Lima disks:"
    limactl disk ls 2>/dev/null || warn "No existing disks found"
    echo
    
    # Show confirmation
    show_confirmation
    
    # Create disks
    local created_count=0
    local skipped_count=0
    
    for i in $(seq 1 "$NUM_DISKS"); do
        local disk_name="${PREFIX}-disk${i}"
        
        if disk_exists "$disk_name"; then
            ((skipped_count++))
        else
            create_disk "$disk_name" "$DISK_SIZE"
            ((created_count++))
        fi
    done
    
    # Summary
    log "Disk creation completed!"
    info "Created: $created_count disks"
    info "Skipped: $skipped_count disks"
    
    log "Updated disk list:"
    limactl disk ls
}

# Run main function
main "$@"