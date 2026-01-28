#!/usr/bin/env bash
# Host operating system detection and platform-specific helpers
# Provides consistent OS detection across all test suites

# Detect the host operating system
# Returns: "linux", "macos", or "wsl"
# Usage:
#   HOST_OS=$(detect_host_os)
detect_host_os() {
  local kernel_name
  kernel_name=$(uname -s)

  case "${kernel_name}" in
    Linux)
      # Check for WSL
      if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    Darwin)
      echo "macos"
      ;;
    *)
      # Default to linux for unknown systems
      echo "linux"
      ;;
  esac
}

# Format Unix timestamp to ISO 8601 format (cross-platform)
# Args:
#   $1: timestamp - Unix timestamp (seconds since epoch)
# Returns: ISO 8601 formatted string (YYYY-MM-DDTHH:MM:SSZ)
# Usage:
#   formatted=$(format_timestamp "${UNIX_TIMESTAMP}")
format_timestamp() {
  local timestamp="$1"

  case "${HOST_OS:-$(detect_host_os)}" in
    macos)
      # macOS uses -r flag for timestamp conversion
      date -r "${timestamp}" -u +%Y-%m-%dT%H:%M:%SZ
      ;;
    *)
      # Linux/WSL use -d flag
      date -d "@${timestamp}" -u +%Y-%m-%dT%H:%M:%SZ
      ;;
  esac
}

# Get the number of CPU cores (cross-platform)
# Returns: Number of available CPU cores
# Usage:
#   cores=$(get_cpu_count)
get_cpu_count() {
  case "${HOST_OS:-$(detect_host_os)}" in
    macos)
      sysctl -n hw.ncpu 2>/dev/null || echo 4
      ;;
    *)
      nproc 2>/dev/null || echo 4
      ;;
  esac
}
