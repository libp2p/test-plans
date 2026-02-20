#!/usr/bin/env bash
# Common test execution utilities
# Used by transport, perf, and hole-punch test runners

# Append lowercase copies of all environment variables
# Input: a string of docker-compose environment variable lines
# Output: the original string with lowercase copies appended
add_lowercase_env_vars() {
  local env_str="$1"
  local lowercase=""
  while IFS= read -r line; do
    if [[ "${line}" =~ ^([[:space:]]*-[[:space:]])([A-Z][A-Z_0-9]*)=(.*)$ ]]; then
      local prefix="${BASH_REMATCH[1]}"
      local var_name="${BASH_REMATCH[2]}"
      local var_value="${BASH_REMATCH[3]}"
      local lower_name=$(echo "${var_name}" | tr '[:upper:]' '[:lower:]')
      lowercase="${lowercase}
${prefix}${lower_name}=${var_value}"
    fi
  done <<< "${env_str}"
  echo "${env_str}${lowercase}"
}

# Generate environment variables for a legacy container (lowercase only).
# Legacy implementations read: transport, ip, is_dialer, redis_addr, security, muxer
# The redis_addr points to the per-test proxy service (TEST_KEY:6379).
#
# Args:
#   $1: is_dialer ("true" or "false")
#   $2: redis_addr (e.g., "a1b2c3d4:6379")
#   $3: transport name
#   $4: secure channel name (or "null")
#   $5: muxer name (or "null")
# Output: docker-compose environment block (printed to stdout)
generate_legacy_env_vars() {
  local is_dialer="$1"
  local redis_addr="$2"
  local transport="$3"
  local secure="$4"
  local muxer="$5"

  local env_str="      - is_dialer=${is_dialer}
      - ip=0.0.0.0
      - redis_addr=${redis_addr}
      - transport=${transport}"

  if ! is_standalone_transport "${transport}"; then
    if [ "${secure}" != "null" ]; then
      env_str="${env_str}
      - security=${secure}"
    fi
    if [ "${muxer}" != "null" ]; then
      env_str="${env_str}
      - muxer=${muxer}"
    fi
  fi

  echo "${env_str}"
}

# Generate environment variables for a modern container (uppercase only).
# Modern implementations read: TRANSPORT, SECURE_CHANNEL, MUXER, IS_DIALER,
# REDIS_ADDR, TEST_KEY, DEBUG.
#
# Args:
#   $1: is_dialer ("true" or "false")
#   $2: redis_addr (e.g., "transport-redis:6379")
#   $3: test_key (8-char hex hash)
#   $4: transport name
#   $5: secure channel name (or "null")
#   $6: muxer name (or "null")
#   $7: debug ("true" or "false")
#   $8+: extra env vars (e.g., "UPLOAD_BYTES=1073741824" "DURATION=20")
# Output: docker-compose environment block (printed to stdout)
generate_modern_env_vars() {
  local is_dialer="$1"
  local redis_addr="$2"
  local test_key="$3"
  local transport="$4"
  local secure="$5"
  local muxer="$6"
  local debug="$7"
  shift 7

  local env_str="      - IS_DIALER=${is_dialer}
      - REDIS_ADDR=${redis_addr}
      - TEST_KEY=${test_key}
      - TRANSPORT=${transport}
      - LISTENER_IP=0.0.0.0
      - DEBUG=${debug}"

  if [ "${secure}" != "null" ]; then
    env_str="${env_str}
      - SECURE_CHANNEL=${secure}"
  fi

  if [ "${muxer}" != "null" ] && ! is_standalone_transport "${transport}"; then
    env_str="${env_str}
      - MUXER=${muxer}"
  fi

  # Append extra env vars
  for extra in "$@"; do
    env_str="${env_str}
      - ${extra}"
  done

  echo "${env_str}"
}
