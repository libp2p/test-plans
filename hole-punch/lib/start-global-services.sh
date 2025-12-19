#!/bin/bash
# Start global services for hole-punch tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$SCRIPT_DIR/../../lib}"

source "$SCRIPT_LIB_DIR/lib-global-services.sh"

# Use global function with hole-punch-specific names
start_redis_service "hole-punch-network" "hole-punch-redis"
