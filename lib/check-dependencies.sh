#!/usr/bin/env bash
# Check for required dependencies and their versions
# Refactored to use data-driven approach with consolidated install instructions

set -euo pipefail

# Source formatting library if not already loaded
if ! type print_message &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_this_script_dir}/lib-output-formatting.sh"
fi

# ============================================================================
# Helper Functions
# ============================================================================

# Function to compare semantic versions
# Returns: 1 if $1 > $2, -1 if $1 < $2, 0 if equal
version_compare() {
  local IFS=.
  local i ver1=($1) ver2=($2)
  # Fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  # Compare each part
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [ -z "${ver2[i]:-}" ]; then
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      echo 1; return
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      echo -1; return
    fi
  done
  echo 0
}

# Universal version parser
# Args: $1=tool, $2=version_type
# Version types:
#   "standard"  - tool --version, extracts X.Y.Z
#   "bash"      - uses $BASH_VERSION variable
#   "gnuplot"   - gnuplot --version, extracts X.Y
#   "compose"   - docker compose version
get_version() {
  local tool="$1"
  local version_type="$2"

  case "$version_type" in
    "standard")
      "$tool" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
      ;;
    "bash")
      echo "${BASH_VERSION%.*}"
      ;;
    "gnuplot")
      gnuplot --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1
      ;;
    "compose")
      docker compose version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
      ;;
  esac
}

# Check if Docker daemon is running
check_docker_daemon() {
  if docker info &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# Detect which docker compose command is available
# Returns: echoes command string ("docker compose" or "docker-compose") or returns 1
detect_docker_compose_cmd() {
  if docker compose version &> /dev/null; then
    echo "docker compose"
    return 0
  elif command -v docker-compose &> /dev/null; then
    echo "docker-compose"
    return 0
  else
    return 1
  fi
}

# Print consolidated install instructions (platform-aware)
print_install_instructions() {
  println
  print_error "Missing or outdated dependencies. Run the following commands to install:"
  println

  local host_os="${HOST_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

  case "${host_os}" in
    macos|darwin)
      print_message "# Install required packages using Homebrew" >&2
      print_message "brew install coreutils flock gnu-sed gnu-tar gzip wget zip unzip bc yq gnuplot pandoc" >&2
      print_message "" >&2
      print_message "# Install Docker Desktop for Mac from:" >&2
      print_message "# https://www.docker.com/products/docker-desktop" >&2
      print_message "" >&2
      print_message "# Note: Some GNU utilities may need to be added to PATH:" >&2
      print_message "# export PATH=\"/usr/local/opt/coreutils/libexec/gnubin:\$PATH\"" >&2
      ;;
    wsl)
      print_message "# Install required system packages (WSL/Ubuntu)" >&2
      print_message "sudo apt-get update" >&2
      print_message "sudo apt-get install -y docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin git patch wget zip unzip bc coreutils util-linux tar gzip" >&2
      print_message "" >&2
      print_message "# Install yq" >&2
      print_message "sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" >&2
      print_message "sudo chmod +x /usr/local/bin/yq" >&2
      print_message "" >&2
      print_message "# Optional: Install for additional features" >&2
      print_message "sudo apt-get install -y gnuplot pandoc" >&2
      ;;
    *)
      # Default: Linux
      print_message "# Install required system packages" >&2
      print_message "sudo apt-get update" >&2
      print_message "sudo apt-get install -y docker-ce docker-ce-cli docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin git patch wget zip unzip bc coreutils util-linux tar gzip" >&2
      print_message "" >&2
      print_message "# Install yq" >&2
      print_message "sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" >&2
      print_message "sudo chmod +x /usr/local/bin/yq" >&2
      print_message "" >&2
      print_message "# Optional: Install for additional features" >&2
      print_message "sudo apt-get install -y gnuplot pandoc" >&2
      ;;
  esac
  println
}

# Column width for tool names (accommodates longest tool name + "...")
TOOL_COL_WIDTH=20

# Print tool check line with aligned columns
# Usage: print_check "toolname" "[OK]" "optional extra info"
print_check() {
  local tool="$1"
  local status="$2"
  local extra="${3:-}"

  # Format: "→ toolname...        [STATUS] extra"
  local tool_col
  tool_col=$(printf "%-${TOOL_COL_WIDTH}s" "${tool}...")

  if [ -n "$extra" ]; then
    print_iem "→" "${tool_col} ${status} ${extra}" >&2
  else
    print_iem "→" "${tool_col} ${status}" >&2
  fi
}

# ============================================================================
# Tool Definitions
# ============================================================================

# Versioned tools: "tool:min_version:version_type"
declare -a VERSIONED_TOOLS=(
  "bash:4.0:bash"
  "docker:20.10.0:standard"
  "yq:4.0.0:standard"
  "git:2.0.0:standard"
)

# Presence-only tools (no version check needed)
declare -a PRESENCE_ONLY_TOOLS=(
  "patch"
  "wget"
  "zip"
  "unzip"
  "cut"
  "bc"
  "sha256sum"
  "timeout"
  "flock"
  "tar"
  "gzip"
  "awk"
  "sed"
  "grep"
  "sort"
  "head"
  "tail"
  "wc"
  "tr"
  "paste"
  "cat"
  "mkdir"
  "cp"
  "mv"
  "rm"
  "chmod"
  "find"
  "xargs"
  "basename"
  "dirname"
  "mktemp"
  "date"
  "sleep"
  "nproc"
  "uname"
  "hostname"
  "ps"
)

# Optional tools: "tool:min_version:version_type" (0 means presence-only)
declare -a OPTIONAL_TOOLS=(
  "gnuplot:5.0:gnuplot"
  "pandoc:0:standard"
)

# ============================================================================
# Main Check Logic
# ============================================================================

HAS_ERROR=false

# Phase 1: Check versioned tools
print_message "Checking versioned tools..."
indent
for entry in "${VERSIONED_TOOLS[@]}"; do
  IFS=':' read -r tool min_version version_type <<< "$entry"

  # Special handling for bash (always available, use $BASH_VERSION)
  if [ "$tool" == "bash" ]; then
    if [ -n "${BASH_VERSION:-}" ]; then
      current_version=$(get_version "$tool" "$version_type")
      if [ "$(version_compare "$current_version" "$min_version")" -ge 0 ]; then
        print_check "$tool" "[OK]" "$current_version"
      else
        print_check "$tool" "[OUTDATED]" "(have $current_version, need $min_version)"
        HAS_ERROR=true
      fi
    else
      print_check "$tool" "[MISSING]"
      HAS_ERROR=true
    fi
    continue
  fi

  # Standard tool check
  if ! command -v "$tool" &> /dev/null; then
    print_check "$tool" "[MISSING]"
    HAS_ERROR=true
  else
    current_version=$(get_version "$tool" "$version_type")
    if [ -n "$current_version" ]; then
      if [ "$(version_compare "$current_version" "$min_version")" -ge 0 ]; then
        print_check "$tool" "[OK]" "$current_version"
      else
        print_check "$tool" "[OUTDATED]" "(have $current_version, need $min_version)"
        HAS_ERROR=true
      fi
    else
      # Could not extract version, assume OK if command exists
      print_check "$tool" "[OK]" "(version unknown)"
    fi
  fi
done

unindent
println

# Phase 2: Check presence-only tools
print_message "Checking required utilities..."
indent
for tool in "${PRESENCE_ONLY_TOOLS[@]}"; do
  if command -v "$tool" &> /dev/null; then
    print_check "$tool" "[OK]"
  else
    print_check "$tool" "[MISSING]"
    HAS_ERROR=true
  fi
done

# Phase 3: If any missing/outdated, print install block and exit
if [ "$HAS_ERROR" = true ]; then
  print_install_instructions
  exit 1
fi

unindent
println

# Phase 4: Check docker daemon
print_message "Checking Docker services..."
indent
if check_docker_daemon; then
  print_check "docker daemon" "[OK]"
else
  print_check "docker daemon" "[NOT RUNNING]"
  echo "" >&2
  print_error "Start docker daemon before running tests"
  exit 1
fi

# Phase 5: Detect docker compose command
DOCKER_COMPOSE_CMD=""
if DOCKER_COMPOSE_CMD=$(detect_docker_compose_cmd); then
  print_check "docker compose" "[OK]" "using '$DOCKER_COMPOSE_CMD'"
  # Export the docker compose command for use by other scripts
  echo "$DOCKER_COMPOSE_CMD" > /tmp/docker-compose-cmd.txt
else
  print_check "docker compose" "[MISSING]"
  print_install_instructions
  exit 1
fi

unindent
println

# Phase 6: Check optional tools (warn but don't fail)
print_message "Checking optional dependencies..."
indent
for entry in "${OPTIONAL_TOOLS[@]}"; do
  IFS=':' read -r tool min_version version_type <<< "$entry"

  if ! command -v "$tool" &> /dev/null; then
    print_check "$tool" "[NOT INSTALLED]"
    continue
  fi

  # If version_type is "presence", just check existence
  if [ "$version_type" == "presence" ] || [ "$min_version" == "0" ]; then
    print_check "$tool" "[OK]"
  else
    current_version=$(get_version "$tool" "$version_type")
    if [ -n "$current_version" ]; then
      if [ "$(version_compare "$current_version" "$min_version")" -ge 0 ]; then
        print_check "$tool" "[OK]" "$current_version"
      else
        print_check "$tool" "[OUTDATED]" "(have $current_version, need $min_version)"
      fi
    else
      print_check "$tool" "[OK]" "(version unknown)"
    fi
  fi
done

unindent
println

# Phase 7: Success
print_success "All required dependencies are satisfied"
exit 0
