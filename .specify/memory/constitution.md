<!--
Sync Impact Report (Constitution Update)
=====================================
Version Change: N/A → 1.0.0 (initial constitution)
Modified Principles: Initial creation of all principles
Added Sections: All sections (initial document)
Removed Sections: None
Templates Requiring Updates:
  ✅ .specify/templates/plan-template.md - Updated constitution reference
  ✅ .specify/templates/spec-template.md - Aligned with declarative principles
  ✅ .specify/templates/tasks-template.md - Aligned with validation-first approach
Follow-up TODOs: None
-->

# Lima-Ops Constitution

## Core Principles

### I. Declarative Configuration
All cluster and infrastructure definitions MUST be declarative and version-controlled. Every aspect of cluster configuration—nodes, resources, disks, deployment types—MUST be expressed in YAML configuration files. No imperative commands for cluster definition; all state described as data.

**Rationale**: Declarative configuration enables reproducibility, version control, and infrastructure-as-code practices. It prevents configuration drift and ensures clusters can be recreated identically.

### II. Validation-First Deployment
Pre-deployment validation is MANDATORY before any infrastructure changes. All configurations MUST be validated for correctness, resource availability, and compatibility before provisioning. Validation includes disk size matching, resource constraints, and dependency checks.

**Rationale**: Lima does not support certain operations (e.g., disk resizing). Early validation prevents failed deployments, wasted resources, and difficult-to-debug runtime errors.

### III. Separation of Concerns
Infrastructure provisioning, VM configuration, and application deployment MUST remain strictly separated. Each phase operates independently with clear boundaries. Infrastructure creates VMs and storage; configuration prepares OS and mounts disks; application layer deploys workloads.

**Rationale**: Separation allows flexibility in deployment choices (Kubernetes vs bare-metal MinIO), enables reuse of infrastructure across deployment types, and simplifies troubleshooting by isolating failure domains.

### IV. Safe Automation
All automation MUST provide dry-run capabilities and clear error messages. Scripts MUST detect existing resources gracefully, prevent destructive operations without confirmation, and provide actionable guidance when errors occur.

**Rationale**: Infrastructure automation carries high risk. Safe defaults, comprehensive validation, and helpful error messages prevent accidental destruction and enable self-service operations.

### V. Shell Script Simplicity
Prefer shell scripts over complex automation frameworks when appropriate. Scripts MUST be readable, well-documented, and follow standard conventions. Error handling MUST be comprehensive with clear exit codes and messages.

**Rationale**: Shell scripts provide transparency, ease of debugging, and minimal dependencies. They're suitable for Lima VM orchestration and align with Unix philosophy of composable tools.

### VI. Idempotent Operations
All operations MUST be idempotent and safely re-runnable. Scripts MUST handle existing resources, partial completions, and retries without side effects. Running the same command twice produces the same result as running it once.

**Rationale**: Infrastructure operations often fail partway through. Idempotence enables safe retries, supports incremental deployment, and reduces operational complexity.

## Infrastructure Standards

### Disk Management
- XFS filesystem for all data disks (performance-optimized)
- UUID-based fstab entries for reliable mounting
- Automatic cleanup of filesystem signatures before formatting
- Mount points follow `/mnt/minio{n}` convention for compatibility
- Smart disk detection excludes system disks (vda) and cidata volumes

### VM Provisioning
- Dynamic inventory generation based on cluster configuration
- SSH access via Lima's native configuration
- Resource specifications (CPU, memory, disk) in configuration files
- Support for multiple isolated clusters simultaneously
- vz vmType for Apple Silicon optimization

### Storage Architecture
- Additional disks created via Lima's disk management
- Raw format for reliability and performance
- Flexible disk naming: `minio-<node>-<disk>`
- Automatic data directory creation at mount points
- Proper unmounting of Lima auto-mounts before processing

## Development Workflow

### Configuration Management
1. Select or create configuration file in `ansible/vars/`
2. Run validation: `./scripts/deploy-cluster.sh validate`
3. Review validation output and fix issues
4. Proceed with deployment only after validation passes

### Deployment Phases
1. **Infrastructure**: Create disks, provision VMs, generate inventory
2. **Configuration**: Format disks, mount storage, install packages
3. **Application**: Deploy Kubernetes or bare-metal MinIO

### Testing Requirements
- Dry-run mode MUST be available for all destructive operations
- Syntax validation for all Ansible playbooks
- Manual testing with small configurations before production use
- Verify cluster status after each deployment phase

### Error Handling
- Clear, actionable error messages with suggested solutions
- Exit codes: 0=success, 1=validation error, 2=runtime error
- Comprehensive logging for troubleshooting
- Helpful guidance for common issues (disk size mismatch, resource constraints)

## Governance

### Constitution Authority
This constitution supersedes ad-hoc practices and defines non-negotiable standards for lima-ops development. All pull requests, code reviews, and deployments MUST verify compliance with these principles.

### Amendment Process
Constitution amendments require:
1. Documentation of proposed changes with rationale
2. Review and approval from maintainers
3. Impact assessment on existing clusters and workflows
4. Migration plan for breaking changes
5. Update to version number following semantic versioning

### Versioning Policy
- **MAJOR**: Backward-incompatible changes to core principles or deployment workflows
- **MINOR**: New principles added, material expansions to existing guidance
- **PATCH**: Clarifications, wording improvements, non-semantic refinements

### Compliance Review
All features and changes MUST be reviewed against:
- Declarative configuration principle (no imperative state changes)
- Validation-first approach (pre-deployment checks)
- Safe automation requirements (dry-run, error messages)
- Idempotent operations (safe re-run)

### Complexity Justification
Deviations from constitution principles MUST be explicitly justified with:
- Specific technical requirement necessitating deviation
- Explanation of why compliant approach is insufficient
- Mitigation strategy for risks introduced
- Plan to return to compliance when possible

### Runtime Guidance
For development and operational guidance, refer to:
- `CLAUDE.md` - Detailed development documentation for AI assistants
- `README.md` - User-facing documentation and quick start
- `docs/` - Extended documentation and troubleshooting guides

**Version**: 1.0.0 | **Ratified**: 2025-10-02 | **Last Amended**: 2025-10-02
