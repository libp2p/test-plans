#!/bin/bash
# Setup and verify remote servers for perf tests
# Checks SSH connectivity and prepares remote servers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "lib/lib-perf.sh"

echo "  → Verifying server configurations..."

# Get all remote servers from images.yaml
remote_servers=$(get_all_remote_servers)

if [ -z "$remote_servers" ]; then
  echo "  → No remote servers configured - using local servers only"
  exit 0
fi

# Verify each remote server
for server_id in $remote_servers; do
  hostname=$(get_remote_hostname "$server_id")
  username=$(get_remote_username "$server_id")

  echo "  → Testing remote server: $server_id"
  echo "    → Host: $username@$hostname"

  # Test SSH connectivity
  if ! verify_remote_server "$server_id"; then
    log_error "Cannot connect to $username@$hostname"
    echo ""
    echo "Please ensure:"
    echo "  1. SSH server is running on $hostname"
    echo "  2. User '$username' exists on remote server"
    echo "  3. SSH key-based authentication is configured"
    echo "  4. Your SSH key is loaded in ssh-agent or configured in ~/.ssh/config"
    echo ""
    echo "Setup instructions: see QUICKSTART.md"
    exit 1
  fi
  echo "  ✓ SSH connection verified"

  # Check Docker on remote server
  echo "  → Checking Docker on $server_id..."
  if ! exec_on_server "$server_id" "docker --version" >/dev/null 2>&1; then
    log_error "Docker not available on $server_id"
    echo ""
    echo "Please install Docker on $hostname:"
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  sudo usermod -aG docker $username"
    echo ""
    exit 1
  fi

  docker_version=$(exec_on_server "$server_id" "docker --version" | cut -d' ' -f3 | tr -d ',')
  echo "  ✓ Docker available: $docker_version"

  # Check Docker permissions (user can run without sudo)
  echo "  → Checking Docker permissions on $server_id..."
  if ! exec_on_server "$server_id" "docker ps" >/dev/null 2>&1; then
    log_error "User '$username' cannot run Docker on $server_id"
    echo ""
    echo "Please add user to docker group on $hostname:"
    echo "  sudo usermod -aG docker $username"
    echo "  # Then log out and back in"
    echo ""
    exit 1
  fi
  echo "  ✓ Docker permissions verified"

  # Create working directory on remote
  echo "  → Creating working directory on $server_id..."
  exec_on_server "$server_id" "mkdir -p /tmp/perf-test" >/dev/null 2>&1 || true
  echo "  ✓ Working directory ready: /tmp/perf-test"

  # Copy helper scripts to remote server
  echo "  → Copying scripts to $server_id..."
  rsync -az --quiet lib/ "${username}@${hostname}:/tmp/perf-test/lib/" || {
    log_error "Failed to copy scripts to $server_id"
    exit 1
  }
  echo "  ✓ Scripts copied"

  log_info "Remote server $server_id ready"
done

echo ""
echo "  ✓ All remote servers verified and ready"
