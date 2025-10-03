#!/bin/bash

# Common utility functions for lima-ops scripts
# Based on proven patterns from legacy scripts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory detection
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Get project root (assuming scripts are in scripts/ subdirectory)
get_project_root() {
    cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd
}

# Logging functions with colors and timestamps
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $1" >&2
    exit 1
}

debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${CYAN}[DEBUG]${NC} $1"
    fi
}

info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}[INFO]${NC} $1"
}

# Progress indicator
show_progress() {
    local message="$1"
    local delay="${2:-0.5}"
    
    echo -n "$message"
    for _ in {1..3}; do
        sleep "$delay"
        echo -n "."
    done
    echo " done!"
}

# Confirmation prompt
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    while true; do
        read -p "$message $prompt " -r response
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            "") 
                if [[ "$default" == "y" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required commands
check_dependencies() {
    local missing_deps=()
    
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -ne 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
    fi
}

# Run command with error handling and logging
run_cmd() {
    local cmd="$*"
    debug "Running: $cmd"
    
    if ! eval "$cmd"; then
        error "Command failed: $cmd"
    fi
}

# Run Ansible playbook with standard options
run_ansible_playbook() {
    local playbook="$1"
    shift
    local extra_vars=()
    
    # Parse additional arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                # Strip 'ansible/' prefix if present since playbooks run from ansible/ directory
                local config_path="$2"
                if [[ "$config_path" =~ ^ansible/ ]]; then
                    config_path="${config_path#ansible/}"
                fi
                extra_vars+=("-e" "config_file=$config_path")
                shift 2
                ;;
            --cluster-name)
                extra_vars+=("-e" "cluster_name_override=$2")
                shift 2
                ;;
            --inventory)
                extra_vars+=("-i" "$2")
                shift 2
                ;;
            *)
                extra_vars+=("$1")
                shift
                ;;
        esac
    done
    
    debug "Running playbook: $playbook with vars: ${extra_vars[*]}"
    
    cd "$PROJECT_ROOT/ansible" || error "Failed to change to ansible directory"
    ansible-playbook "$playbook" "${extra_vars[@]}"
}

# Check if file exists, exit with error if not
require_file() {
    local file="$1"
    local description="${2:-File}"
    
    if [[ ! -f "$file" ]]; then
        error "$description not found: $file"
    fi
}

# Check if directory exists, create if needed
ensure_dir() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        debug "Creating directory: $dir"
        mkdir -p "$dir" || error "Failed to create directory: $dir"
    fi
}

# Extract deployment type from config file
get_deployment_type() {
    local config_file="$1"
    
    require_file "$config_file" "Configuration file"
    
    local deployment_type
    deployment_type=$(grep -A1 '^deployment:' "$config_file" | grep 'type:' | cut -d'"' -f2 | tr -d ' ')
    
    if [[ -z "$deployment_type" ]]; then
        warn "Could not determine deployment type from config file, defaulting to 'kubernetes'"
        deployment_type="kubernetes"
    fi
    
    echo "$deployment_type"
}

# Display banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ██╗     ██╗███╗   ███╗ █████╗       ██████╗ ██████╗ ███████╗
    ██║     ██║████╗ ████║██╔══██╗     ██╔═══██╗██╔══██╗██╔════╝
    ██║     ██║██╔████╔██║███████║     ██║   ██║██████╔╝███████╗
    ██║     ██║██║╚██╔╝██║██╔══██║     ██║   ██║██╔═══╝ ╚════██║
    ███████╗██║██║ ╚═╝ ██║██║  ██║     ╚██████╔╝██║     ███████║
    ╚══════╝╚═╝╚═╝     ╚═╝╚═╝  ╚═╝      ╚═════╝ ╚═╝     ╚══════╝
                                                                 
EOF
    echo -e "${NC}"
    echo -e "${BLUE}Lima-Ops: Comprehensive Lima VM Management${NC}"
    echo -e "${BLUE}Supports both Kubernetes and Bare-metal MinIO clusters${NC}"
    echo
}