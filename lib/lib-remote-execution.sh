#!/bin/bash
# Remote execution utilities for SSH/SCP operations
# Preserves output aesthetics during remote builds

# Test SSH connectivity to a remote server
test_ssh_connectivity() {
    local username="$1"
    local hostname="$2"
    local timeout="${3:-5}"  # Default 5 second timeout

    # Try SSH with a simple echo command
    if ssh -o ConnectTimeout=$timeout -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "${username}@${hostname}" "echo 2>&1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Test connectivity to all remote servers in images.yaml
# Returns 0 if all servers are reachable, 1 if any fail
test_all_remote_servers() {
    local impls_yaml="${1:-images.yaml}"
    local get_server_config_fn="$2"  # Function name to get server config
    local get_remote_hostname_fn="$3"  # Function name to get hostname
    local get_remote_username_fn="$4"  # Function name to get username
    local is_remote_server_fn="$5"  # Function name to check if remote

    if [ ! -f "$impls_yaml" ]; then
        echo "✗ Error: $impls_yaml not found"
        return 1
    fi

    echo "╲ Testing remote server connectivity..."
    echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"

    local impl_count=$(yq eval '.implementations | length' "$impls_yaml")
    local has_error=false
    declare -A tested_servers  # Track servers we've already tested

    for ((i=0; i<impl_count; i++)); do
        local impl_id=$(yq eval ".implementations[$i].id" "$impls_yaml")
        local server_id=$($get_server_config_fn "$impl_id")

        # Skip if not a remote server
        if ! $is_remote_server_fn "$server_id"; then
            continue
        fi

        # Skip if already tested this server
        if [ -n "${tested_servers[$server_id]:-}" ]; then
            continue
        fi

        local hostname=$($get_remote_hostname_fn "$server_id")
        local username=$($get_remote_username_fn "$server_id")

        echo -n "→ Testing ${server_id} (${username}@${hostname})... "

        if test_ssh_connectivity "$username" "$hostname" 5; then
            echo "✓ Connected"
            tested_servers[$server_id]=1
        else
            echo "✗ Failed"
            echo "  Troubleshooting:"
            echo "  1. Check SSH key: ssh ${username}@${hostname}"
            echo "  2. Verify server is running"
            echo "  3. Check network connectivity"
            has_error=true
            tested_servers[$server_id]=0
        fi
    done

    echo ""

    if [ "$has_error" == "true" ]; then
        echo "╲ ✗ Some remote servers are unreachable"
        echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
        return 1
    else
        echo "╲ ✓ All remote servers are reachable"
        echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
        return 0
    fi
}

# Copy file to remote server
copy_to_remote() {
    local file="$1"
    local username="$2"
    local hostname="$3"
    local remote_path="$4"

    scp -q "$file" "${username}@${hostname}:${remote_path}" || return 1
}

# Execute command on remote server
exec_on_remote() {
    local username="$1"
    local hostname="$2"
    local command="$3"

    ssh "${username}@${hostname}" "$command"
}

# Build image on remote server (with aesthetic preservation)
build_on_remote() {
    local yaml_file="$1"
    local username="$2"
    local hostname="$3"
    local build_script="$4"

    local remote_dir="/tmp/docker-build-$$"
    local remote_yaml="$remote_dir/build.yaml"
    local remote_script="$remote_dir/build-single-image.sh"
    local remote_lib="$remote_dir/lib-image-building.sh"

    echo "→ Building on remote: ${username}@${hostname}"

    # Create remote directory
    exec_on_remote "$username" "$hostname" "mkdir -p $remote_dir" || return 1

    # Copy YAML file
    echo "  → Copying build parameters..."
    copy_to_remote "$yaml_file" "$username" "$hostname" "$remote_yaml" || return 1

    # Copy build script
    echo "  → Copying build script..."
    copy_to_remote "$build_script" "$username" "$hostname" "$remote_script" || return 1

    # Copy lib-image-building.sh (required by build script)
    local script_dir=$(dirname "$build_script")
    local lib_script="$script_dir/lib-image-building.sh"
    if [ -f "$lib_script" ]; then
        copy_to_remote "$lib_script" "$username" "$hostname" "$remote_lib" || return 1
    fi

    # Execute build with aesthetic preservation
    # -tt forces pseudo-terminal allocation to preserve output formatting
    echo "  → Executing remote build..."
    if ! ssh -tt "${username}@${hostname}" "bash $remote_script $remote_yaml" 2>&1; then
        # Cleanup on failure
        exec_on_remote "$username" "$hostname" "rm -rf $remote_dir" 2>/dev/null || true
        return 1
    fi

    # Cleanup on success
    exec_on_remote "$username" "$hostname" "rm -rf $remote_dir" 2>/dev/null || true

    return 0
}
