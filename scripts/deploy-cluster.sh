#!/bin/bash

# Lima-Ops: Main cluster deployment orchestration script
# Replaces Makefile-based workflows with clear shell script logic

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utility libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"  
source "$SCRIPT_DIR/lib/validation.sh"

# Default values
CONFIG_FILE=""
CLUSTER_NAME=""
COMMAND=""
FORCE=false
DRY_RUN=false
VERBOSE=false

# Usage information
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Lima-Ops: Comprehensive Lima VM Management
Supports both Kubernetes and Bare-metal MinIO clusters

COMMANDS:
  full-setup        Complete end-to-end cluster deployment (default)
  provision         Create Lima VMs and generate inventory
  configure         Configure VMs with disk mounting
  deploy            Deploy applications (K8s or bare-metal MinIO)
  validate          Validate configuration and requirements
  create-disks      Create Lima disks for cluster
  mount-disks       Mount additional disks on VMs
  status            Show cluster status
  destroy           Destroy cluster resources
  list-configs      Show available configuration files

OPTIONS:
  -c, --config FILE     Configuration file (required)
  -n, --name NAME       Cluster name (required)
  -f, --force           Force operation without prompts
  -d, --dry-run         Show what would be done without executing
  -v, --verbose         Enable verbose output
  -h, --help           Show this help message

EXAMPLES:
  # Quick deployment
  $0 --config ansible/vars/dev-small.yml --name dev
  
  # Step-by-step deployment
  $0 provision --config ansible/vars/dev-small.yml --name dev
  $0 configure --name dev  
  $0 deploy --name dev
  
  # Dry run
  $0 --dry-run --config ansible/vars/dev-small.yml --name dev
  
  # Interactive configuration selection
  $0 list-configs

CONFIGURATION FILES:
  ansible/vars/dev-small.yml        Small development cluster
  ansible/vars/prod-large.yml       Large production cluster  
  ansible/vars/baremetal-simple.yml Simple bare-metal MinIO
  ansible/vars/cluster_config.yml   Default Kubernetes cluster
  ansible/vars/baremetal_config.yml Default bare-metal cluster

EOF
}

# Parse command line arguments
parse_args() {
    # First argument might be a command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
        case "$1" in
            full-setup|provision|configure|deploy|validate|create-disks|mount-disks|status|destroy|list-configs)
                COMMAND="$1"
                shift
                ;;
        esac
    fi
    
    # Default command
    if [[ -z "$COMMAND" ]]; then
        COMMAND="full-setup"
    fi
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--name)
                CLUSTER_NAME="$2"  
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                export DEBUG=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Validate required arguments
validate_args() {
    case "$COMMAND" in
        list-configs)
            # No validation needed for list-configs
            return 0
            ;;
        status|destroy)
            # These commands only need cluster name
            if [[ -z "$CLUSTER_NAME" ]]; then
                error "Cluster name is required for '$COMMAND' command. Use --name option."
            fi
            ;;
        configure|mount-disks|deploy)
            # These commands need cluster name but might not need config
            if [[ -z "$CLUSTER_NAME" ]]; then
                error "Cluster name is required for '$COMMAND' command. Use --name option."
            fi
            ;;
        *)
            # Most commands need both config and cluster name
            if [[ -z "$CONFIG_FILE" ]]; then
                error "Configuration file is required. Use --config option or run '$0 list-configs'."
            fi
            
            if [[ -z "$CLUSTER_NAME" ]]; then
                error "Cluster name is required. Use --name option."
            fi
            ;;
    esac
}

# Execute provision command
cmd_provision() {
    log "Provisioning Lima VMs and generating inventory..."
    
    run_ansible_playbook \
        "playbooks/infrastructure/provision_vms.yml" \
        --config "$CONFIG_FILE" \
        --cluster-name "$CLUSTER_NAME"
    
    log "VM provisioning completed successfully"
}

# Execute create-disks command  
cmd_create_disks() {
    log "Creating Lima disks for cluster..."
    
    run_ansible_playbook \
        "playbooks/infrastructure/manage_disks.yml" \
        --config "$CONFIG_FILE" \
        --cluster-name "$CLUSTER_NAME"
    
    log "Disk creation completed successfully"
}

# Execute configure command
cmd_configure() {
    log "Configuring VMs..."
    
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${CLUSTER_NAME}.ini"
    require_file "$inventory_file" "Inventory file"
    
    local config_args=()
    if [[ -n "$CONFIG_FILE" ]]; then
        config_args=("--config" "$CONFIG_FILE")
    fi
    
    run_ansible_playbook \
        "playbooks/configuration/configure_vms.yml" \
        --inventory "$inventory_file" \
        "${config_args[@]}" \
        -e "target_cluster=$CLUSTER_NAME"
    
    log "VM configuration completed successfully"  
}

# Execute mount-disks command
cmd_mount_disks() {
    log "Mounting additional disks on VMs..."
    
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${CLUSTER_NAME}.ini"
    require_file "$inventory_file" "Inventory file"
    
    run_ansible_playbook \
        "playbooks/configuration/mount_disks.yml" \
        --inventory "$inventory_file" \
        -e "target_cluster=$CLUSTER_NAME"
    
    log "Disk mounting completed successfully"
}

# Execute deploy command
cmd_deploy() {
    log "Deploying applications..."
    
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${CLUSTER_NAME}.ini"
    require_file "$inventory_file" "Inventory file"
    
    # Determine deployment type from config or inventory
    local deployment_type=""
    if [[ -n "$CONFIG_FILE" ]]; then
        deployment_type=$(get_deployment_type "$CONFIG_FILE")
    else
        # Try to determine from existing resources or prompt user
        warn "No configuration file specified, cannot determine deployment type"
        echo "Available deployment types:"
        echo "  1) kubernetes - Kubernetes cluster with AIStor"
        echo "  2) baremetal - Bare-metal MinIO cluster"
        
        while true; do
            read -p "Select deployment type (1-2): " -r choice
            case "$choice" in
                1) deployment_type="kubernetes"; break ;;
                2) deployment_type="baremetal"; break ;;
                *) echo "Please select 1 or 2." ;;
            esac
        done
    fi
    
    case "$deployment_type" in
        kubernetes)
            log "Deploying Kubernetes-based MinIO cluster..."
            run_ansible_playbook \
                "playbooks/kubernetes/deploy_kubernetes_minio.yml" \
                --inventory "$inventory_file" \
                -e "target_cluster=$CLUSTER_NAME"
            ;;
        baremetal)
            log "Deploying bare-metal MinIO cluster..."
            run_ansible_playbook \
                "playbooks/baremetal/deploy_baremetal_minio.yml" \
                --inventory "$inventory_file" \
                -e "target_cluster=$CLUSTER_NAME"
            ;;
        *)
            error "Unknown deployment type: $deployment_type"
            ;;
    esac
    
    log "Application deployment completed successfully"
}

# Execute validate command
cmd_validate() {
    log "Running pre-deployment validation..."
    
    run_ansible_playbook \
        "playbooks/infrastructure/validate_setup.yml" \
        --config "$CONFIG_FILE"
    
    log "Validation completed successfully"
}

# Execute status command
cmd_status() {
    log "Checking cluster status for: $CLUSTER_NAME"
    echo
    
    # Show Lima VMs
    echo -e "${BLUE}Lima VMs:${NC}"
    local vms
    vms=$(limactl list | grep "^${CLUSTER_NAME}-" || echo "No VMs found for cluster: $CLUSTER_NAME")
    echo "$vms"
    echo
    
    # Show Lima disks
    echo -e "${BLUE}Lima Disks:${NC}"
    local disks
    disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' | grep "minio-${CLUSTER_NAME}-" || echo "No disks found for cluster: $CLUSTER_NAME")
    echo "$disks"
    echo
    
    # Show inventory
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${CLUSTER_NAME}.ini"
    if [[ -f "$inventory_file" ]]; then
        echo -e "${BLUE}Inventory File:${NC} $inventory_file"
    else
        echo -e "${YELLOW}Inventory File:${NC} Not found"
    fi
}

# Execute destroy command
cmd_destroy() {
    warn "This will COMPLETELY destroy all resources for cluster: $CLUSTER_NAME"
    echo "This includes:"
    echo "  - All Lima VMs with prefix '$CLUSTER_NAME-'"
    echo "  - All Lima disks with prefix 'minio-$CLUSTER_NAME-' (ALL DATA WILL BE LOST)"
    echo "  - Inventory file"
    echo
    echo -e "${RED}WARNING: All data stored on cluster disks will be permanently lost!${NC}"
    echo
    
    if [[ "$FORCE" != "true" ]] && ! confirm "Are you sure you want to destroy cluster '$CLUSTER_NAME'?" "n"; then
        log "Destroy operation cancelled"
        return 0
    fi
    
    log "Destroying cluster: $CLUSTER_NAME"
    
    # Stop and delete VMs
    local vms
    vms=$(limactl list -q | grep "^${CLUSTER_NAME}-" || true)
    if [[ -n "$vms" ]]; then
        while IFS= read -r vm; do
            log "Stopping and deleting VM: $vm"
            limactl stop "$vm" 2>/dev/null || true
            limactl delete "$vm" 2>/dev/null || true
        done <<< "$vms"
    else
        log "No VMs found for cluster: $CLUSTER_NAME"
    fi
    
    # Delete disks
    local disks
    disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' | grep "minio-${CLUSTER_NAME}-" || true)
    if [[ -n "$disks" ]]; then
        while IFS= read -r disk; do
            if [[ -n "$disk" ]]; then
                log "Deleting disk: $disk"
                limactl disk delete "$disk" 2>/dev/null || warn "Failed to delete disk $disk"
            fi
        done <<< "$disks"
    else
        log "No disks found for cluster: $CLUSTER_NAME"
    fi
    
    # Remove inventory file
    local inventory_file="$PROJECT_ROOT/ansible/inventory/${CLUSTER_NAME}.ini"
    if [[ -f "$inventory_file" ]]; then
        log "Removing inventory file: $inventory_file"
        rm -f "$inventory_file"
    fi
    
    log "Cluster '$CLUSTER_NAME' destroyed successfully"
}

# Execute list-configs command
cmd_list_configs() {
    show_banner
    list_configs
}

# Execute full-setup command (main workflow)
cmd_full_setup() {
    log "Starting full cluster setup for: $CLUSTER_NAME"
    echo
    
    # Run pre-deployment validation
    pre_deployment_validation "$CONFIG_FILE" "$CLUSTER_NAME"
    echo
    
    # Execute the deployment pipeline
    log "Executing deployment pipeline..."
    echo
    
    show_progress "Creating Lima disks" 1
    cmd_create_disks
    echo
    
    show_progress "Provisioning VMs" 2  
    cmd_provision
    echo
    
    show_progress "Configuring VMs" 1
    cmd_configure
    echo
    
    show_progress "Mounting disks" 1
    cmd_mount_disks
    echo
    
    show_progress "Deploying applications" 3
    cmd_deploy
    echo
    
    log "Full cluster setup completed successfully!"
    echo
    
    # Show final status
    cmd_status
    
    # Show next steps
    echo -e "${GREEN}Next Steps:${NC}"
    local deployment_type
    deployment_type=$(get_deployment_type "$CONFIG_FILE")
    
    case "$deployment_type" in
        kubernetes)
            echo "  1. Check cluster status: kubectl get nodes"
            echo "  2. Access MinIO Console via port forwarding (check VM ports)"
            echo "  3. Configure ingress if needed"
            ;;
        baremetal)
            echo "  1. Check MinIO status: ssh into VMs and run 'systemctl status minio'"
            echo "  2. Access MinIO Console via port forwarding (check VM ports)"
            echo "  3. Configure clients with MinIO endpoints"
            ;;
    esac
    
    echo "  4. View cluster details: $0 status --name $CLUSTER_NAME"
}

# Main execution function
main() {
    parse_args "$@"
    validate_args
    
    # Set dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No actual changes will be made"
        export ANSIBLE_CHECK_MODE="true"
    fi
    
    # Execute the requested command
    case "$COMMAND" in
        full-setup)
            cmd_full_setup
            ;;
        provision)
            cmd_provision
            ;;
        create-disks)
            cmd_create_disks
            ;;
        configure) 
            cmd_configure
            ;;
        mount-disks)
            cmd_mount_disks
            ;;
        deploy)
            cmd_deploy
            ;;
        validate)
            cmd_validate
            ;;
        status)
            cmd_status
            ;;
        destroy)
            cmd_destroy
            ;;
        list-configs)
            cmd_list_configs
            ;;
        *)
            error "Unknown command: $COMMAND"
            ;;
    esac
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"