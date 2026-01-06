#!/bin/bash
# Common library for Docker image naming conventions
# Used by both build-images.sh and create-snapshot.sh

# Get the Docker image name for an implementation
# Usage: get_impl_image_name <impl_id> <test_type>
# test_type: "transport", "hole-punch", or "perf"
get_impl_image_name() {
    local impl_id="$1"
    local test_type="$2"

    case "$test_type" in
        transport)
            echo "transport-interop-${impl_id}"
            ;;
        hole-punch)
            echo "hole-punch-peer-${impl_id}"
            ;;
        perf)
            echo "perf-${impl_id}"
            ;;
        *)
            echo "Error: Unknown test type: $test_type" >&2
            return 1
            ;;
    esac
}

# Get the Docker image name for a relay
# Usage: get_relay_image_name <relay_id> <test_type>
get_relay_image_name() {
    local relay_id="$1"
    local test_type="$2"

    case "$test_type" in
        hole-punch)
            echo "hole-punch-relay-${relay_id}"
            ;;
        *)
            echo "Error: Relays not supported for test type: $test_type" >&2
            return 1
            ;;
    esac
}

# Get the Docker image name for a router
# Usage: get_router_image_name <router_id> <test_type>
get_router_image_name() {
    local router_id="$1"
    local test_type="$2"

    case "$test_type" in
        hole-punch)
            echo "hole-punch-router-${router_id}"
            ;;
        *)
            echo "Error: Routers not supported for test type: $test_type" >&2
            return 1
            ;;
    esac
}

# Detect test type from current directory
# Returns "transport", "hole-punch", or "perf"
detect_test_type() {
    local pwd_basename=$(basename "$(pwd)")

    if [ "$pwd_basename" = "transport" ]; then
        echo "transport"
    elif [ "$pwd_basename" = "hole-punch" ]; then
        echo "hole-punch"
    elif [ "$pwd_basename" = "perf" ]; then
        echo "perf"
    else
        # Try to detect from parent directory structure
        if [ -f "images.yaml" ] && grep -q "hole-punch" images.yaml 2>/dev/null; then
            echo "hole-punch"
        elif [ -f "images.yaml" ] && grep -q "transport" images.yaml 2>/dev/null; then
            echo "transport"
        elif [ -f "images.yaml" ] && grep -q "perf" images.yaml 2>/dev/null; then
            echo "perf"
        else
            echo "Error: Could not detect test type from directory" >&2
            return 1
        fi
    fi
}
