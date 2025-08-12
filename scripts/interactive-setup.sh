#!/bin/bash

# Interactive setup wizard for lima-ops
# Guides users through configuration selection and deployment

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utility libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Selected values
SELECTED_CONFIG=""
SELECTED_CLUSTER_NAME=""
SELECTED_ACTION=""

# Main menu
show_main_menu() {
    show_banner
    echo -e "${BLUE}Interactive Setup Wizard${NC}"
    echo "This wizard will guide you through setting up a Lima cluster."
    echo
    echo "What would you like to do?"
    echo -e "  ${GREEN}1)${NC} Deploy a new cluster (full setup)"
    echo -e "  ${GREEN}2)${NC} Provision VMs only (infrastructure)"
    echo -e "  ${GREEN}3)${NC} Configure existing VMs"
    echo -e "  ${GREEN}4)${NC} Deploy applications to existing cluster"
    echo -e "  ${GREEN}5)${NC} Show cluster status"
    echo -e "  ${GREEN}6)${NC} Destroy a cluster"
    echo -e "  ${GREEN}7)${NC} Exit"
    echo
}

# Select action
select_action() {
    while true; do
        show_main_menu
        read -p "Enter your choice (1-7): " -r choice
        case "$choice" in
            1) SELECTED_ACTION="full-setup"; break ;;
            2) SELECTED_ACTION="provision"; break ;;
            3) SELECTED_ACTION="configure"; break ;;
            4) SELECTED_ACTION="deploy"; break ;;
            5) SELECTED_ACTION="status"; break ;;
            6) SELECTED_ACTION="destroy"; break ;;
            7) log "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice. Please enter a number between 1 and 7." ;;
        esac
    done
}

# Get cluster name from user
get_cluster_name() {
    echo
    echo -e "${BLUE}Cluster Name Selection${NC}"
    echo
    
    if [[ -n "$SELECTED_CONFIG" ]]; then
        local suggested_name
        suggested_name=$(suggest_cluster_name "$SELECTED_CONFIG")
        echo "Based on your configuration file, we suggest: ${GREEN}$suggested_name${NC}"
        echo
        
        if confirm "Use suggested cluster name '$suggested_name'?" "y"; then
            SELECTED_CLUSTER_NAME="$suggested_name"
            return 0
        fi
    fi
    
    while true; do
        read -p "Enter cluster name: " -r cluster_name
        
        if [[ -z "$cluster_name" ]]; then
            echo "Cluster name cannot be empty."
            continue
        fi
        
        if [[ ! "$cluster_name" =~ ^[a-zA-Z0-9]+$ ]]; then
            echo "Cluster name must contain only letters and numbers (no dashes or special characters)."
            continue
        fi
        
        SELECTED_CLUSTER_NAME="$cluster_name"
        break
    done
}

# Get existing cluster name for actions that don't need config
get_existing_cluster_name() {
    echo
    echo -e "${BLUE}Existing Clusters${NC}"
    echo
    
    # Find existing clusters from Lima VMs (extract everything before first dash)
    local existing_clusters
    existing_clusters=$(limactl list -q | sed 's/-.*//' | sort -u | grep -v '^$' || true)
    
    if [[ -z "$existing_clusters" ]]; then
        echo "No existing clusters found."
        
        while true; do
            read -p "Enter cluster name manually: " -r cluster_name
            
            if [[ -z "$cluster_name" ]]; then
                echo "Cluster name cannot be empty."
                continue
            fi
            
            if [[ ! "$cluster_name" =~ ^[a-zA-Z0-9]+$ ]]; then
                echo "Cluster name must contain only letters and numbers (no dashes or special characters)."
                continue
            fi
            
            SELECTED_CLUSTER_NAME="$cluster_name"
            return 0
        done
    fi
    
    echo "Found existing clusters:"
    local cluster_array=()
    while IFS= read -r cluster; do
        if [[ -n "$cluster" ]]; then
            cluster_array+=("$cluster")
        fi
    done <<< "$existing_clusters"
    
    for i in "${!cluster_array[@]}"; do
        echo -e "  ${GREEN}$((i+1)))${NC} ${cluster_array[i]}"
    done
    
    echo -e "  ${GREEN}$((${#cluster_array[@]}+1)))${NC} Enter manually"
    echo
    
    while true; do
        read -p "Select cluster (1-$((${#cluster_array[@]}+1))): " -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ "$choice" -ge 1 && "$choice" -le ${#cluster_array[@]} ]]; then
                SELECTED_CLUSTER_NAME="${cluster_array[$((choice-1))]}"
                break
            elif [[ "$choice" -eq $((${#cluster_array[@]}+1)) ]]; then
                while true; do
                    read -p "Enter cluster name manually: " -r cluster_name
                    
                    if [[ -z "$cluster_name" ]]; then
                        echo "Cluster name cannot be empty."
                        continue
                    fi
                    
                    if [[ ! "$cluster_name" =~ ^[a-zA-Z0-9]+$ ]]; then
                        echo "Cluster name must contain only letters and numbers (no dashes or special characters)."
                        continue
                    fi
                    
                    SELECTED_CLUSTER_NAME="$cluster_name"
                    break 2
                done
            fi
        fi
        
        echo "Invalid choice. Please enter a number between 1 and $((${#cluster_array[@]}+1))."
    done
}

# Configuration selection workflow
select_configuration() {
    echo
    echo -e "${BLUE}Configuration File Selection${NC}"
    echo
    
    SELECTED_CONFIG=$(select_config)
    
    if [[ -n "$SELECTED_CONFIG" ]]; then
        echo
        echo -e "${GREEN}Selected configuration:${NC} $SELECTED_CONFIG"
        show_config "$SELECTED_CONFIG"
        echo
        
        if ! confirm "Use this configuration?" "y"; then
            select_configuration
        fi
    fi
}

# Show deployment preview
show_deployment_preview() {
    echo
    echo -e "${BLUE}Deployment Preview${NC}"
    echo "======================================"
    echo -e "Action: ${GREEN}$SELECTED_ACTION${NC}"
    echo -e "Configuration: ${GREEN}$SELECTED_CONFIG${NC}"
    echo -e "Cluster Name: ${GREEN}$SELECTED_CLUSTER_NAME${NC}"
    
    local deployment_type
    deployment_type=$(get_deployment_type "$SELECTED_CONFIG")
    echo -e "Deployment Type: ${CYAN}$deployment_type${NC}"
    echo
    
    # Show what will happen
    case "$SELECTED_ACTION" in
        full-setup)
            echo "This will:"
            echo "  1. Validate configuration and system requirements"
            echo "  2. Create Lima disks for the cluster"
            echo "  3. Provision Lima VMs"
            echo "  4. Configure VMs with disk mounting"
            if [[ "$deployment_type" == "kubernetes" ]]; then
                echo "  5. Deploy Kubernetes cluster with AIStor"
            else
                echo "  5. Deploy bare-metal MinIO cluster"
            fi
            ;;
        provision)
            echo "This will:"
            echo "  1. Validate configuration"
            echo "  2. Create Lima disks for the cluster"
            echo "  3. Provision Lima VMs"
            echo "  4. Generate inventory file"
            ;;
        configure)
            echo "This will:"
            echo "  1. Configure existing VMs"
            echo "  2. Mount additional disks"
            ;;
        deploy)
            echo "This will:"
            if [[ "$deployment_type" == "kubernetes" ]]; then
                echo "  1. Deploy Kubernetes cluster with AIStor"
            else
                echo "  1. Deploy bare-metal MinIO cluster"
            fi
            ;;
    esac
    
    echo
}

# Execute the selected action
execute_action() {
    local cmd_args=()
    
    # Build command arguments
    cmd_args+=("$SELECTED_ACTION")
    
    if [[ -n "$SELECTED_CONFIG" ]]; then
        cmd_args+=("--config" "$SELECTED_CONFIG")
    fi
    
    if [[ -n "$SELECTED_CLUSTER_NAME" ]]; then
        cmd_args+=("--name" "$SELECTED_CLUSTER_NAME")
    fi
    
    # Add verbose flag for better user experience
    cmd_args+=("--verbose")
    
    echo
    log "Executing: $SCRIPT_DIR/deploy-cluster.sh ${cmd_args[*]}"
    echo
    
    # Execute the main deployment script
    exec "$SCRIPT_DIR/deploy-cluster.sh" "${cmd_args[@]}"
}

# Main workflow
main() {
    # Step 1: Select what to do
    select_action
    
    # Step 2: Get required information based on action
    case "$SELECTED_ACTION" in
        full-setup|provision)
            select_configuration
            get_cluster_name
            ;;
        configure|deploy)
            # Try to detect from existing clusters first
            get_existing_cluster_name
            
            # For deploy, we might need config to determine deployment type
            if [[ "$SELECTED_ACTION" == "deploy" ]]; then
                echo
                if confirm "Do you have the configuration file used for this cluster?" "y"; then
                    select_configuration
                fi
            fi
            ;;
        status|destroy)
            get_existing_cluster_name
            ;;
    esac
    
    # Step 3: Show preview and confirm
    if [[ "$SELECTED_ACTION" != "status" ]]; then
        show_deployment_preview
        
        if ! confirm "Proceed with this action?" "y"; then
            log "Action cancelled by user"
            exit 0
        fi
    fi
    
    # Step 4: Execute
    execute_action
}

# Handle script interruption
trap 'error "Interactive setup interrupted by user"' INT TERM

# Run main function
main "$@"