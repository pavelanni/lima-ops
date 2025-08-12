#!/bin/bash

# Validation functions for lima-ops scripts

# Common functions are sourced by main script

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Required commands
    local required_commands=(
        "limactl"
        "ansible"
        "ansible-playbook"
    )
    
    check_dependencies "${required_commands[@]}"
    
    # Check Lima installation
    if ! limactl --version >/dev/null 2>&1; then
        error "Lima is not properly installed or not in PATH"
    fi
    
    # Check Ansible installation
    local ansible_version
    ansible_version=$(ansible --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+')
    if [[ -z "$ansible_version" ]]; then
        error "Could not determine Ansible version"
    fi
    
    log "System requirements check passed"
    debug "Lima version: $(limactl --version 2>/dev/null | head -n1)"
    debug "Ansible version: $ansible_version"
}

# Check project structure
check_project_structure() {
    log "Checking project structure..."
    
    local project_root
    project_root="$PROJECT_ROOT"
    
    # Required directories
    local required_dirs=(
        "$project_root/ansible"
        "$project_root/ansible/playbooks"
        "$project_root/ansible/vars"
        "$project_root/ansible/templates"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error "Required directory not found: $dir"
        fi
    done
    
    # Required files
    local required_files=(
        "$project_root/ansible/ansible.cfg"
        "$project_root/ansible/playbooks/infrastructure/provision_vms.yml"
        "$project_root/ansible/playbooks/configuration/configure_vms.yml"
        "$project_root/ansible/templates/lima_vm.yml.j2"
    )
    
    for file in "${required_files[@]}"; do
        require_file "$file" "Required project file"
    done
    
    log "Project structure check passed"
}

# Check for conflicting resources
check_existing_resources() {
    local cluster_name="$1"
    
    log "Checking for existing resources for cluster: $cluster_name"
    
    # Check for existing VMs
    local existing_vms
    existing_vms=$(limactl list -q | grep "^${cluster_name}-" || true)
    
    if [[ -n "$existing_vms" ]]; then
        warn "Found existing VMs for cluster '$cluster_name':"
        echo "$existing_vms" | sed 's/^/    /'
        echo
        
        if confirm "Do you want to continue? This may cause conflicts." "n"; then
            warn "Continuing with existing VMs - conflicts may occur"
        else
            error "Aborted due to existing VMs"
        fi
    fi
    
    # Check for existing disks
    local existing_disks
    existing_disks=$(limactl disk ls 2>/dev/null | awk 'NR>1 {print $1}' | grep "minio-${cluster_name}-" || true)
    
    if [[ -n "$existing_disks" ]]; then
        warn "Found existing disks for cluster '$cluster_name':"
        echo "$existing_disks" | sed 's/^/    /'
        echo
        
        if confirm "Do you want to continue? Existing disks will be reused." "y"; then
            log "Continuing with existing disks"
        else
            error "Aborted due to existing disks"
        fi
    fi
    
    # Check inventory file
    local project_root
    project_root="$PROJECT_ROOT"
    local inventory_file="$project_root/inventory/${cluster_name}.ini"
    
    if [[ -f "$inventory_file" ]]; then
        warn "Found existing inventory file: $inventory_file"
        if confirm "Do you want to regenerate the inventory file?" "y"; then
            log "Will regenerate inventory file"
        else
            log "Will use existing inventory file"
        fi
    fi
}

# Validate cluster configuration before deployment
validate_cluster_config() {
    local config_file="$1"
    local cluster_name="$2"
    
    log "Validating cluster configuration..."
    
    # Validate cluster name format (no dashes allowed)
    if [[ "$cluster_name" =~ - ]]; then
        error "Cluster name '$cluster_name' cannot contain dashes. 

Cluster names with dashes cause issues with VM name parsing.
Please use a cluster name without dashes, such as:
  - '$cluster_name' → '${cluster_name//-/}'  
  - 'dev' instead of 'dev-cluster'
  - 'production' instead of 'prod-env'"
    fi
    
    local project_root
    project_root="$PROJECT_ROOT"
    
    # Make path absolute if relative
    if [[ ! "$config_file" = /* ]]; then
        config_file="$project_root/$config_file"
    fi
    
    require_file "$config_file" "Configuration file"
    
    # Check if cluster name matches config
    if command_exists yq; then
        local config_cluster_name
        config_cluster_name=$(yq eval '.kubernetes_cluster.name // ""' "$config_file" 2>/dev/null)
        
        if [[ -n "$config_cluster_name" && "$config_cluster_name" != "$cluster_name" ]]; then
            warn "Cluster name mismatch:"
            warn "  Command line: $cluster_name"
            warn "  Config file: $config_cluster_name"
            warn "  Using command line value: $cluster_name"
        fi
    fi
    
    # Validate node configuration
    if command_exists yq; then
        local node_count
        node_count=$(yq eval '.kubernetes_cluster.nodes | length' "$config_file" 2>/dev/null || echo 0)
        
        if [[ "$node_count" -eq 0 ]]; then
            error "No nodes defined in configuration file"
        fi
        
        if [[ "$node_count" -gt 10 ]]; then
            warn "Large number of nodes ($node_count) - this may take a long time"
            if ! confirm "Continue with $node_count nodes?" "n"; then
                error "Aborted due to large node count"
            fi
        fi
        
        # Check for control plane nodes
        local control_plane_count
        control_plane_count=$(yq eval '[.kubernetes_cluster.nodes[] | select(.role == "control-plane")] | length' "$config_file" 2>/dev/null || echo 0)
        
        if [[ "$control_plane_count" -eq 0 ]]; then
            error "No control-plane nodes defined in configuration"
        fi
        
        # Validate disk sizes against existing VMs (Lima doesn't support disk resize)
        validate_disk_sizes "$config_file" "$cluster_name"
    fi
    
    log "Cluster configuration validation passed"
}

# Check available system resources
check_system_resources() {
    local config_file="$1"
    
    log "Checking system resources..."
    
    if ! command_exists yq; then
        warn "Cannot check resource requirements - yq not available"
        return 0
    fi
    
    local project_root
    project_root="$PROJECT_ROOT"
    
    # Make path absolute if relative
    if [[ ! "$config_file" = /* ]]; then
        config_file="$project_root/$config_file"
    fi
    
    # Calculate total CPU and memory requirements
    local total_cpus=0
    local total_memory_gb=0
    
    local node_count
    node_count=$(yq eval '.kubernetes_cluster.nodes | length' "$config_file" 2>/dev/null || echo 0)
    
    for ((i=0; i<node_count; i++)); do
        local cpus
        local memory
        cpus=$(yq eval ".kubernetes_cluster.nodes[$i].cpus" "$config_file" 2>/dev/null || echo 1)
        memory=$(yq eval ".kubernetes_cluster.nodes[$i].memory" "$config_file" 2>/dev/null || echo "1GiB")
        
        total_cpus=$((total_cpus + cpus))
        
        # Convert memory to GB (simplified)
        if [[ "$memory" =~ ([0-9]+)GiB ]]; then
            total_memory_gb=$((total_memory_gb + ${BASH_REMATCH[1]}))
        elif [[ "$memory" =~ ([0-9]+)MB ]]; then
            total_memory_gb=$((total_memory_gb + ${BASH_REMATCH[1]} / 1024))
        fi
    done
    
    # Check available system resources (macOS)
    if command -v sysctl >/dev/null 2>&1; then
        local available_cpus
        local available_memory_gb
        
        available_cpus=$(sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
        available_memory_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))
        
        if [[ "$available_cpus" != "unknown" && "$total_cpus" -gt "$available_cpus" ]]; then
            warn "Requested CPUs ($total_cpus) exceeds available CPUs ($available_cpus)"
        fi
        
        if [[ "$available_memory_gb" -gt 0 && "$total_memory_gb" -gt $((available_memory_gb / 2)) ]]; then
            warn "Requested memory (${total_memory_gb}GB) is more than half of available memory (${available_memory_gb}GB)"
        fi
    fi
    
    log "Resource requirements: ${total_cpus} CPUs, ${total_memory_gb}GB memory"
}

# Validate disk sizes against existing VMs to prevent Lima resize conflicts
validate_disk_sizes() {
    local config_file="$1" 
    local cluster_name="$2"
    
    debug "Validating disk sizes for cluster: $cluster_name"
    
    # Use yq to get node information directly
    if ! command_exists yq; then
        warn "Cannot validate disk sizes - yq not available"
        return 0
    fi
    
    local node_count
    node_count=$(yq eval '.kubernetes_cluster.nodes | length' "$config_file" 2>/dev/null || echo 0)
    
    for ((i=0; i<node_count; i++)); do
        local node_name
        local config_disk_size
        node_name=$(yq eval ".kubernetes_cluster.nodes[$i].name" "$config_file" 2>/dev/null || echo "unknown")
        config_disk_size=$(yq eval ".kubernetes_cluster.nodes[$i].disk_size" "$config_file" 2>/dev/null || echo "")
        
        if [[ -z "$config_disk_size" ]]; then
            continue
        fi
        
        local full_vm_name="${cluster_name}-${node_name}"
        
        # Check if VM exists
        if limactl list -q | grep -q "^${full_vm_name}$"; then
            # Get existing VM disk size
            local existing_disk_size
            existing_disk_size=$(limactl list | grep "^${full_vm_name}" | awk '{print $6}' || echo "")
            
            if [[ -n "$existing_disk_size" && "$existing_disk_size" != "$config_disk_size" ]]; then
                error "Disk size mismatch for VM '$full_vm_name':
  Configuration file: $config_disk_size
  Existing VM: $existing_disk_size
  
Lima does not support disk resizing. Please either:
1. Update the configuration file to match existing VM: disk_size: \"$existing_disk_size\"
2. Destroy the existing VM and recreate: ./scripts/deploy-cluster.sh destroy --name $cluster_name"
            fi
        fi
        
        # Warn about non-standard disk sizes
        case "$config_disk_size" in
            "8GiB"|"10GiB"|"20GiB"|"50GiB")
                # Standard sizes - OK
                ;;
            *)
                warn "Non-standard disk size '$config_disk_size' for node '$node_name'. Consider using standard sizes: 8GiB, 10GiB, 20GiB, or 50GiB"
                ;;
        esac
    done
    
    debug "Disk size validation completed"
}

# Pre-deployment validation
pre_deployment_validation() {
    local config_file="$1"
    local cluster_name="$2"
    
    show_banner
    
    log "Starting pre-deployment validation for cluster: $cluster_name"
    echo
    
    check_system_requirements
    check_project_structure  
    validate_cluster_config "$config_file" "$cluster_name"
    check_system_resources "$config_file"
    check_existing_resources "$cluster_name"
    
    echo
    log "Pre-deployment validation completed successfully"
    
    if ! confirm "Proceed with deployment?" "y"; then
        error "Deployment aborted by user"
    fi
}