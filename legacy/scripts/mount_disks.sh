#!/bin/bash

# Mount and format disks for MinIO cluster
# Based on pavelanni/lima_templates
# 
# This script detects available disks, formats them with XFS,
# creates mount points, and adds fstab entries for MinIO storage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

# Function to detect available disks
detect_disks() {
    log "Detecting available disks..."
    
    # Get all block devices, excluding vda (system disk) and sr0 (cdrom)
    DISKS=$(lsblk -ndo NAME | grep -E '^vd[b-z]$' | grep -v sr0 | sort)
    
    if [ -z "$DISKS" ]; then
        error "No additional disks found!"
    fi
    
    log "Found disks: $DISKS"
    echo "$DISKS"
}

# Function to check if disk has cidata label (Lima metadata)
is_cidata_disk() {
    local disk=$1
    if blkid /dev/$disk 2>/dev/null | grep -q 'LABEL="cidata"'; then
        return 0
    fi
    return 1
}

# Function to unmount disk if mounted
unmount_disk() {
    local disk=$1
    
    # Check if any partitions of this disk are mounted
    local mounted_partitions=$(mount | grep "^/dev/${disk}" | awk '{print $1}' || true)
    
    if [ -n "$mounted_partitions" ]; then
        log "Unmounting existing partitions for $disk..."
        for partition in $mounted_partitions; do
            umount "$partition" || warn "Failed to unmount $partition"
        done
    fi
}

# Function to format and mount a single disk
format_and_mount_disk() {
    local disk=$1
    local mount_number=$2
    local mount_point="/mnt/minio${mount_number}"
    
    log "Processing disk: /dev/$disk -> $mount_point"
    
    # Skip if this is a cidata disk
    if is_cidata_disk "$disk"; then
        warn "Skipping $disk (Lima cidata disk)"
        return 0
    fi
    
    # Unmount any existing partitions
    unmount_disk "$disk"
    
    # Remove existing fstab entries for this disk
    sed -i "/\/dev\/${disk}/d" /etc/fstab
    
    # Wipe existing filesystem signatures
    wipefs -a "/dev/$disk" 2>/dev/null || warn "Could not wipe signatures on $disk"
    
    # Create GPT partition table
    log "Creating partition table on /dev/$disk..."
    parted -s "/dev/$disk" mklabel gpt
    parted -s "/dev/$disk" mkpart primary 0% 100%
    
    # Wait for partition to be created
    sleep 2
    partprobe "/dev/$disk"
    
    # Format with XFS
    log "Formatting /dev/${disk}1 with XFS..."
    mkfs.xfs -f "/dev/${disk}1"
    
    # Get UUID
    local uuid=$(blkid -s UUID -o value "/dev/${disk}1")
    log "Disk UUID: $uuid"
    
    # Create mount point
    mkdir -p "$mount_point"
    
    # Add to fstab using UUID
    echo "UUID=$uuid $mount_point xfs defaults 0 2" >> /etc/fstab
    
    # Mount the filesystem
    mount "$mount_point"
    
    # Create MinIO data directory
    mkdir -p "${mount_point}/data"
    
    # Set ownership if minio-user exists
    if id "minio-user" >/dev/null 2>&1; then
        chown -R minio-user:minio-user "${mount_point}/data"
        log "Set ownership of ${mount_point}/data to minio-user"
    else
        warn "minio-user not found, keeping root ownership"
    fi
    
    log "Successfully mounted $disk to $mount_point"
}

# Main function
main() {
    log "Starting disk mounting process..."
    
    # Detect disks
    local disks=$(detect_disks)
    local mount_number=1
    
    # Process each disk
    for disk in $disks; do
        format_and_mount_disk "$disk" "$mount_number"
        ((mount_number++))
    done
    
    log "Disk mounting completed!"
    log "Mounted filesystems:"
    df -h | grep "/mnt/minio" || warn "No MinIO mounts found"
    
    log "MinIO data directories:"
    ls -la /mnt/minio*/data 2>/dev/null || warn "No MinIO data directories found"
}

# Run main function
main "$@"