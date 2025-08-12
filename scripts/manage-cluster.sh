#!/bin/bash

# Cluster management utility script
# Provides quick commands for common cluster operations

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utility libraries
source "$SCRIPT_DIR/lib/common.sh"

# Usage information
usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Cluster Management Utilities

COMMANDS:
  list              List all Lima clusters
  status CLUSTER    Show detailed status for a cluster
  logs CLUSTER VM   Show logs for a specific VM
  ssh CLUSTER VM    SSH into a specific VM
  port-forward      Show port forwarding information
  destroy CLUSTER   Destroy a specific cluster (VMs, disks, inventory)
  cleanup           Clean up stopped/failed VMs and orphaned disks

OPTIONS:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output

EXAMPLES:
  $0 list                    # List all clusters
  $0 status dev              # Show status for 'dev' cluster
  $0 ssh dev worker-01       # SSH into dev-worker-01 VM
  $0 logs dev control-plane-01  # Show logs for control plane
  $0 destroy dev             # Destroy 'dev' cluster completely
  $0 cleanup                 # Clean up orphaned resources

EOF
}

# List all clusters
cmd_list() {
    show_banner
    echo -e "${BLUE}Lima Clusters Overview${NC}"
    echo

    # Get all Lima VMs
    local all_vms
    all_vms=$(limactl list 2>/dev/null || echo "")

    if [[ -z "$all_vms" ]] || [[ "$all_vms" == *"No instances found"* ]]; then
        echo "No Lima VMs found."
        return 0
    fi

    # Extract cluster names (everything before the first dash)
    local clusters
    clusters=$(limactl list -q | sed 's/-.*//' | sort -u | grep -v '^$' || true)

    if [[ -z "$clusters" ]]; then
        echo "No clusters found."
        return 0
    fi

    echo -e "${GREEN}Found Clusters:${NC}"
    echo

    while IFS= read -r cluster; do
        if [[ -n "$cluster" ]]; then
            echo -e "${CYAN}Cluster: $cluster${NC}"

            # Show VMs for this cluster
            local cluster_vms
            cluster_vms=$(limactl list | grep "^$cluster-" || echo "")

            if [[ -n "$cluster_vms" ]]; then
                echo "$cluster_vms" | while IFS= read -r line; do
                    echo "  $line"
                done
            fi

            # Show disks for this cluster
            local cluster_disks
            cluster_disks=$(limactl disk ls 2>/dev/null | grep "minio-$cluster-" || true)

            if [[ -n "$cluster_disks" ]]; then
                echo -e "  ${BLUE}Disks:${NC}"
                echo "$cluster_disks" | while IFS= read -r line; do
                    echo "    $line"
                done
            fi

            # Check for inventory file
            local inventory_file="$PROJECT_ROOT/inventory/${cluster}.ini"
            if [[ -f "$inventory_file" ]]; then
                echo -e "  ${GREEN}Inventory:${NC} ✓ Present"
            else
                echo -e "  ${YELLOW}Inventory:${NC} ✗ Missing"
            fi

            echo
        fi
    done <<< "$clusters"
}

# Show detailed status for a specific cluster
cmd_status() {
    local cluster_name="$1"

    if [[ -z "$cluster_name" ]]; then
        error "Cluster name is required for status command"
    fi

    echo -e "${BLUE}Detailed Status for Cluster: $cluster_name${NC}"
    echo "================================================"
    echo

    # Show VMs with detailed information
    echo -e "${CYAN}Virtual Machines:${NC}"
    local vms
    vms=$(limactl list | grep "^$cluster_name-" || echo "No VMs found for cluster: $cluster_name")

    if [[ "$vms" != *"No VMs found"* ]]; then
        echo "$vms"

        # Show additional VM details
        echo
        echo -e "${CYAN}VM Details:${NC}"
        limactl list -q | grep "^$cluster_name-" | while IFS= read -r vm; do
            echo -e "\n${GREEN}VM: $vm${NC}"

            # VM status
            local vm_status
            vm_status=$(limactl list | grep "^$vm" | awk '{print $2}' || echo "Unknown")
            echo "  Status: $vm_status"

            # SSH info
            if [[ "$vm_status" == "Running" ]]; then
                local ssh_info
                ssh_info=$(limactl list | grep "^$vm" | awk '{print $3}' || echo "N/A")
                echo "  SSH: $ssh_info"

                # Show disk usage if VM is running
                echo "  Disk Usage:"
                limactl shell "$vm" df -h 2>/dev/null | grep -E '(Filesystem|/mnt)' | sed 's/^/    /' || echo "    Unable to get disk usage"
            fi
        done
    else
        echo "$vms"
    fi

    echo
    echo -e "${CYAN}Lima Disks:${NC}"
    local disks
    disks=$(limactl disk ls 2>/dev/null | grep "minio-$cluster_name-" || echo "No disks found for cluster: $cluster_name")
    echo "$disks"

    echo
    echo -e "${CYAN}Inventory File:${NC}"
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${cluster_name}.ini"
    if [[ -f "$inventory_file" ]]; then
        echo -e "  Location: ${GREEN}$inventory_file${NC}"
        echo "  Contents:"
        cat "$inventory_file" | sed 's/^/    /'
    else
        echo -e "  Status: ${YELLOW}Not found${NC}"
        echo "  Location: $inventory_file"
    fi

    echo
    echo -e "${CYAN}Port Forwarding:${NC}"
    limactl list -q | grep "^$cluster_name-" | while IFS= read -r vm; do
        if [[ $(limactl list | grep "^$vm" | awk '{print $2}') == "Running" ]]; then
            echo "  $vm:"
            # Try to get port forwarding info from Lima config
            local lima_config="$HOME/.lima/$vm/lima.yaml"
            if [[ -f "$lima_config" ]] && command_exists yq; then
                yq eval '.portForwards[]? | "    " + (.hostPort | tostring) + " -> " + (.guestPort | tostring) + " (" + (.guestIP // "127.0.0.1") + ")"' "$lima_config" 2>/dev/null || echo "    No port forwards configured"
            else
                echo "    Port forward info not available"
            fi
        fi
    done
}

# Show logs for a specific VM
cmd_logs() {
    local cluster_name="$1"
    local vm_name="$2"

    if [[ -z "$cluster_name" ]] || [[ -z "$vm_name" ]]; then
        error "Both cluster name and VM name are required for logs command"
    fi

    local full_vm_name="${cluster_name}-${vm_name}"

    log "Showing logs for: $full_vm_name"
    echo

    # Check if VM exists and is running
    if ! limactl list -q | grep -q "^$full_vm_name$"; then
        error "VM not found: $full_vm_name"
    fi

    local vm_status
    vm_status=$(limactl list | grep "^$full_vm_name" | awk '{print $2}')

    if [[ "$vm_status" != "Running" ]]; then
        warn "VM is not running (status: $vm_status)"

        # Show Lima logs
        echo -e "${BLUE}Lima Logs:${NC}"
        local lima_log="$HOME/.lima/$full_vm_name/ha.stderr.log"
        if [[ -f "$lima_log" ]]; then
            tail -50 "$lima_log"
        else
            echo "No Lima logs found"
        fi
    else
        # Show system logs
        echo -e "${BLUE}System Logs (last 50 lines):${NC}"
        limactl shell "$full_vm_name" sudo journalctl -n 50 --no-pager || echo "Could not retrieve system logs"

        echo
        echo -e "${BLUE}Cloud-init Logs:${NC}"
        limactl shell "$full_vm_name" sudo cat /var/log/cloud-init-output.log 2>/dev/null | tail -20 || echo "No cloud-init logs found"
    fi
}

# SSH into a specific VM
cmd_ssh() {
    local cluster_name="$1"
    local vm_name="$2"

    if [[ -z "$cluster_name" ]] || [[ -z "$vm_name" ]]; then
        error "Both cluster name and VM name are required for SSH command"
    fi

    local full_vm_name="${cluster_name}-${vm_name}"

    # Check if VM exists
    if ! limactl list -q | grep -q "^$full_vm_name$"; then
        error "VM not found: $full_vm_name"
    fi

    # Check if VM is running
    local vm_status
    vm_status=$(limactl list | grep "^$full_vm_name" | awk '{print $2}')

    if [[ "$vm_status" != "Running" ]]; then
        error "VM is not running (status: $vm_status). Please start it first with: limactl start $full_vm_name"
    fi

    log "Connecting to: $full_vm_name"

    # SSH into the VM
    exec limactl shell "$full_vm_name"
}

# Show port forwarding information
cmd_port_forward() {
    echo -e "${BLUE}Port Forwarding Information${NC}"
    echo "=================================="
    echo

    # Get all running VMs
    local running_vms
    running_vms=$(limactl list | grep "Running" | awk '{print $1}' || true)

    if [[ -z "$running_vms" ]]; then
        echo "No running VMs found."
        return 0
    fi

    while IFS= read -r vm; do
        if [[ -n "$vm" ]]; then
            echo -e "${GREEN}VM: $vm${NC}"

            # Get SSH port
            local ssh_info
            ssh_info=$(limactl list | grep "^$vm" | awk '{print $3}')
            echo "  SSH: $ssh_info"

            # Get configured port forwards from Lima config
            local lima_config="$HOME/.lima/$vm/lima.yaml"
            if [[ -f "$lima_config" ]] && command_exists yq; then
                local forwards
                forwards=$(yq eval '.portForwards[]?' "$lima_config" 2>/dev/null || true)
                if [[ -n "$forwards" ]]; then
                    echo "  Port Forwards:"
                    yq eval '.portForwards[] | "    " + (.hostPort | tostring) + " -> " + (.guestPort | tostring) + " (" + (.guestIP // "127.0.0.1") + ")"' "$lima_config" 2>/dev/null
                fi
            fi
            echo
        fi
    done <<< "$running_vms"

    echo "Access services using: http://localhost:<host-port>"
}

# Cleanup orphaned resources
cmd_cleanup() {
    warn "This will clean up stopped/failed VMs and orphaned disks"
    echo

    if ! confirm "Proceed with cleanup?" "n"; then
        log "Cleanup cancelled"
        return 0
    fi

    log "Starting cleanup process..."

    # Clean up stopped VMs
    local stopped_vms
    stopped_vms=$(limactl list | grep -E "(Stopped|Broken)" | awk '{print $1}' || true)

    if [[ -n "$stopped_vms" ]]; then
        echo -e "${BLUE}Stopped/Broken VMs:${NC}"
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                echo "  $vm"
                if confirm "Delete $vm?" "n"; then
                    limactl delete "$vm" 2>/dev/null || warn "Failed to delete $vm"
                fi
            fi
        done <<< "$stopped_vms"
    else
        log "No stopped/broken VMs found"
    fi

    echo

    # List orphaned disks (disks not attached to any VM)
    log "Checking for orphaned disks..."
    local all_disks
    all_disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' || true)
    local all_vms
    all_vms=$(limactl list -q || true)

    if [[ -n "$all_disks" ]]; then
        echo -e "${BLUE}Potentially Orphaned Disks:${NC}"
        while IFS= read -r disk; do
            if [[ -n "$disk" ]] && [[ "$disk" =~ ^minio- ]]; then
                # Extract cluster name from disk name (everything before first dash after minio-)
                local cluster_from_disk
                cluster_from_disk=$(echo "$disk" | sed 's/^minio-//' | sed 's/-.*//')

                # Check if any VM from this cluster exists
                local cluster_has_vms=false
                while IFS= read -r vm; do
                    if [[ -n "$vm" ]] && [[ "$vm" =~ ^${cluster_from_disk}- ]]; then
                        cluster_has_vms=true
                        break
                    fi
                done <<< "$all_vms"

                if [[ "$cluster_has_vms" == "false" ]]; then
                    echo "  $disk (cluster: $cluster_from_disk)"
                    if confirm "Delete orphaned disk $disk?" "n"; then
                        limactl disk delete "$disk" 2>/dev/null || warn "Failed to delete disk $disk"
                    fi
                fi
            fi
        done <<< "$all_disks"
    fi

    log "Cleanup completed"
}

# Destroy a specific cluster
cmd_destroy() {
    local cluster_name="${1:-}"

    if [[ -z "$cluster_name" ]]; then
        echo -e "${RED}Error: Cluster name is required for destroy command${NC}"
        echo
        echo "Usage: $0 destroy CLUSTER_NAME"
        echo
        echo "Available clusters:"
        # Show available clusters to help the user
        local existing_clusters
        existing_clusters=$(limactl list -q | sed 's/-.*//' | sort -u | grep -v '^$' || true)

        if [[ -n "$existing_clusters" ]]; then
            while IFS= read -r cluster; do
                if [[ -n "$cluster" ]]; then
                    echo "  - $cluster"
                fi
            done <<< "$existing_clusters"
        else
            echo "  No clusters found"
        fi

        echo
        echo "Example: $0 destroy dev"
        exit 1
    fi

    # Validate cluster name format
    if [[ "$cluster_name" =~ - ]]; then
        error "Invalid cluster name '$cluster_name'. Cluster names cannot contain dashes."
    fi

    echo -e "${BLUE}Destroy Cluster: $cluster_name${NC}"
    echo "==============================="
    echo

    # Check if cluster exists
    local cluster_vms
    cluster_vms=$(limactl list -q | grep "^$cluster_name-" || true)

    local cluster_disks
    cluster_disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' | grep "minio-$cluster_name-" || true)

    local inventory_file="$PROJECT_ROOT/ansible/inventory/${cluster_name}.ini"

    if [[ -z "$cluster_vms" && -z "$cluster_disks" && ! -f "$inventory_file" ]]; then
        warn "No resources found for cluster '$cluster_name'"
        echo "  - No VMs found"
        echo "  - No disks found"
        echo "  - No inventory file found"
        echo
        log "Nothing to destroy for cluster '$cluster_name'"
        return 0
    fi

    # Show what will be destroyed
    echo -e "${YELLOW}Resources to be destroyed:${NC}"

    if [[ -n "$cluster_vms" ]]; then
        echo -e "\n${RED}VMs:${NC}"
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                local vm_status
                vm_status=$(limactl list | grep "^$vm" | awk '{print $2}' || echo "Unknown")
                echo "  - $vm ($vm_status)"
            fi
        done <<< "$cluster_vms"
    fi

    if [[ -n "$cluster_disks" ]]; then
        echo -e "\n${RED}Disks:${NC}"
        while IFS= read -r disk; do
            if [[ -n "$disk" ]]; then
                echo "  - $disk"
            fi
        done <<< "$cluster_disks"
    fi

    if [[ -f "$inventory_file" ]]; then
        echo -e "\n${RED}Inventory:${NC}"
        echo "  - $inventory_file"
    fi

    echo
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo

    if ! confirm "Are you sure you want to destroy cluster '$cluster_name'?" "n"; then
        log "Destroy operation cancelled by user"
        return 0
    fi

    echo
    log "Destroying cluster: $cluster_name"

    # Stop and delete VMs
    if [[ -n "$cluster_vms" ]]; then
        echo
        log "Stopping and deleting VMs..."
        while IFS= read -r vm; do
            if [[ -n "$vm" ]]; then
                local vm_status
                vm_status=$(limactl list | grep "^$vm" | awk '{print $2}' || echo "Unknown")

                if [[ "$vm_status" == "Running" ]]; then
                    info "Stopping VM: $vm"
                    limactl stop "$vm" 2>/dev/null || warn "Failed to stop $vm"
                fi

                info "Deleting VM: $vm"
                limactl delete "$vm" 2>/dev/null || warn "Failed to delete $vm"
            fi
        done <<< "$cluster_vms"
    fi

    # Delete disks
    if [[ -n "$cluster_disks" ]]; then
        echo
        log "Deleting disks..."
        while IFS= read -r disk; do
            if [[ -n "$disk" ]]; then
                info "Deleting disk: $disk"
                limactl disk delete "$disk" 2>/dev/null || warn "Failed to delete disk $disk"
            fi
        done <<< "$cluster_disks"
    fi

    # Remove inventory file
    if [[ -f "$inventory_file" ]]; then
        echo
        log "Removing inventory file..."
        info "Deleting: $inventory_file"
        rm -f "$inventory_file" || warn "Failed to delete inventory file"
    fi

    echo
    log "Cluster '$cluster_name' destroyed successfully"

    # Verify destruction
    local remaining_vms
    remaining_vms=$(limactl list -q --log-level error | grep "^$cluster_name-" || true)
    local remaining_disks
    remaining_disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' | grep "minio-$cluster_name-" || true)

    if [[ -n "$remaining_vms" || -n "$remaining_disks" ]]; then
        echo
        warn "Some resources may not have been completely removed:"
        [[ -n "$remaining_vms" ]] && echo "  Remaining VMs: $remaining_vms"
        [[ -n "$remaining_disks" ]] && echo "  Remaining disks: $remaining_disks"
        echo
        echo "You can run '$0 cleanup' to clean up any remaining orphaned resources."
    else
        echo
        echo -e "${GREEN}✓ All resources for cluster '$cluster_name' have been successfully removed.${NC}"
    fi
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    # Handle help first
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    local command="$1"
    shift

    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                export DEBUG=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    # Execute command
    case "$command" in
        list)
            cmd_list
            ;;
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        ssh)
            cmd_ssh "$@"
            ;;
        port-forward)
            cmd_port_forward
            ;;
        destroy)
            cmd_destroy "$@"
            ;;
        cleanup)
            cmd_cleanup
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
parse_args "$@"