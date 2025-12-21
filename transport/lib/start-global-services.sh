#!/bin/bash
# Start global services for transport tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$SCRIPT_DIR/../../lib}"

source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
source "$SCRIPT_LIB_DIR/lib-global-services.sh"

print_header "Starting global services..."
start_redis_service "transport-network" "transport-redis"
echo "  ✓ Started transport-redis"
