#!/bin/bash

# Configuration file management for lima-ops scripts

# Common functions are sourced by main script

# Default configuration files
DEFAULT_CONFIGS=(
    "ansible/vars/cluster_config.yml"
    "ansible/vars/baremetal_config.yml" 
    "ansible/vars/dev-small.yml"
    "ansible/vars/prod-large.yml"
    "ansible/vars/baremetal-simple.yml"
)

# List available configuration files  
list_configs() {
    local project_root="$PROJECT_ROOT"
    
    echo "Available configuration files:"
    echo
    
    for config in "${DEFAULT_CONFIGS[@]}"; do
        local full_path="$project_root/$config"
        if [[ -f "$full_path" ]]; then
            local deployment_type
            deployment_type=$(get_deployment_type "$full_path")
            echo -e "  ${GREEN}✓${NC} $config ${CYAN}($deployment_type)${NC}"
        else
            echo -e "  ${RED}✗${NC} $config ${RED}(missing)${NC}"
        fi
    done
    
    echo
    echo "Custom configuration files:"
    find "$project_root/ansible/vars" -name "*.yml" -not -path "*/group_vars/*" | while read -r config; do
        local rel_path
        rel_path=$(realpath --relative-to="$project_root" "$config" 2>/dev/null || echo "$config")
        
        # Skip if already listed in defaults
        local skip=false
        for default_config in "${DEFAULT_CONFIGS[@]}"; do
            if [[ "$rel_path" == "$default_config" ]]; then
                skip=true
                break
            fi
        done
        
        if [[ "$skip" == "false" ]]; then
            local deployment_type
            deployment_type=$(get_deployment_type "$config")
            echo -e "  ${YELLOW}→${NC} $rel_path ${CYAN}($deployment_type)${NC}"
        fi
    done
}

# Validate configuration file
validate_config() {
    local config_file="$1"
    local project_root="$PROJECT_ROOT"
    
    # Make path absolute if relative
    if [[ ! "$config_file" = /* ]]; then
        config_file="$project_root/$config_file"
    fi
    
    require_file "$config_file" "Configuration file"
    
    debug "Validating configuration file: $config_file"
    
    # Check YAML syntax
    if command_exists yq; then
        if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
            error "Invalid YAML syntax in configuration file: $config_file"
        fi
    elif command_exists python3; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            error "Invalid YAML syntax in configuration file: $config_file"
        fi
    else
        warn "Cannot validate YAML syntax - yq or python3 not available"
    fi
    
    # Check required fields
    local required_fields=("kubernetes_cluster" "kubernetes_cluster.nodes")
    local deployment_type
    deployment_type=$(get_deployment_type "$config_file")
    
    if [[ "$deployment_type" == "kubernetes" ]]; then
        required_fields+=("aistor")
    elif [[ "$deployment_type" == "baremetal" ]]; then
        required_fields+=("minio")
    fi
    
    for field in "${required_fields[@]}"; do
        if command_exists yq; then
            if ! yq eval "has(\"${field//./\".\"}\")  and .${field//./\".\"} != null" "$config_file" >/dev/null 2>&1; then
                error "Missing required field '$field' in configuration file: $config_file"
            fi
        fi
    done
    
    log "Configuration file validation passed: $config_file"
    return 0
}

# Show configuration summary
show_config() {
    local config_file="$1"
    local cluster_name="${2:-}"
    local project_root="$PROJECT_ROOT"
    
    # Make path absolute if relative
    if [[ ! "$config_file" = /* ]]; then
        config_file="$project_root/$config_file"
    fi
    
    require_file "$config_file" "Configuration file"
    
    local deployment_type
    deployment_type=$(get_deployment_type "$config_file")
    
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo -e "  Config File: ${GREEN}$config_file${NC}"
    echo -e "  Deployment Type: ${CYAN}$deployment_type${NC}"
    
    if [[ -n "$cluster_name" ]]; then
        echo -e "  Cluster Name: ${GREEN}$cluster_name${NC}"
    fi
    
    # Extract node information
    if command_exists yq; then
        local node_count
        node_count=$(yq eval '.kubernetes_cluster.nodes | length' "$config_file" 2>/dev/null || echo "unknown")
        echo -e "  Number of Nodes: ${GREEN}$node_count${NC}"
        
        echo -e "\n${BLUE}Node Configuration:${NC}"
        yq eval '.kubernetes_cluster.nodes[] | "  - " + .name + " (" + .role + "): " + (.cpus | tostring) + " CPUs, " + .memory + " memory, " + .disk_size + " disk"' "$config_file" 2>/dev/null || echo "  Unable to parse node configuration"
    fi
    
    echo
}

# Select configuration interactively
select_config() {
    echo -e "${BLUE}Select a configuration file:${NC}"
    echo
    
    local project_root="$PROJECT_ROOT"
    
    local configs=()
    local descriptions=()
    
    # Add default configs that exist
    for config in "${DEFAULT_CONFIGS[@]}"; do
        local full_path="$project_root/$config"
        if [[ -f "$full_path" ]]; then
            configs+=("$config")
            local deployment_type
            deployment_type=$(get_deployment_type "$full_path")
            case "$config" in
                *dev-small*)
                    descriptions+=("Small development cluster ($deployment_type)")
                    ;;
                *prod-large*)
                    descriptions+=("Large production cluster ($deployment_type)")
                    ;;
                *baremetal-simple*)
                    descriptions+=("Simple bare-metal MinIO cluster ($deployment_type)")
                    ;;
                *cluster_config*)
                    descriptions+=("Default Kubernetes cluster ($deployment_type)")
                    ;;
                *baremetal_config*)
                    descriptions+=("Default bare-metal cluster ($deployment_type)")
                    ;;
                *)
                    descriptions+=("Configuration file ($deployment_type)")
                    ;;
            esac
        fi
    done
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        error "No configuration files found"
    fi
    
    # Display options
    for i in "${!configs[@]}"; do
        echo -e "  ${GREEN}$((i+1)))${NC} ${configs[i]} - ${descriptions[i]}"
    done
    
    echo
    while true; do
        read -p "Enter your choice (1-${#configs[@]}): " -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#configs[@]} ]]; then
            echo "${configs[$((choice-1))]}"
            return 0
        else
            echo "Invalid choice. Please enter a number between 1 and ${#configs[@]}."
        fi
    done
}

# Generate a cluster name suggestion based on config
suggest_cluster_name() {
    local config_file="$1"
    
    local basename
    basename=$(basename "$config_file" .yml)
    
    case "$basename" in
        dev-small)
            echo "dev"
            ;;
        prod-large) 
            echo "production"
            ;;
        baremetal-simple)
            echo "storage"
            ;;
        cluster_config)
            echo "k8s-cluster"
            ;;
        baremetal_config)
            echo "minio-cluster"
            ;;
        *)
            echo "$basename"
            ;;
    esac
}