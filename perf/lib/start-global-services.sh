#!/bin/bash
# Start global services for perf tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$SCRIPT_DIR/../../lib}"

source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
source "$SCRIPT_LIB_DIR/lib-global-services.sh"

print_header "Staring global services..."
start_redis_service "perf-network" "perf-redis"
