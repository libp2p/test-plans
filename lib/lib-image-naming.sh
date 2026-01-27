#!/usr/bin/env bash
# Common library for Docker image naming conventions
# Used by both image building and snapshot creation

# Get the Docker image name for any entity type
# Usage: get_image_name <test_type> <section> <id>
#
# Parameters:
#   test_type: "transport", "hole-punch", or "perf"
#   section: "implementations", "baselines", "relays", "routers"
#   id: entity identifier (e.g., "rust-v0.56")
#
# Returns: <test_type>-<section>-<id>
#
# Examples:
#   get_image_name "perf" "implementations" "rust-v0.56"
#     → "perf-implementations-rust-v0.56"
#   get_image_name "hole-punch" "relays" "go-relay"
#     → "hole-punch-relays-go-relay"
get_image_name() {
    local test_type="${1}"
    local section="${2}"
    local id="${3}"

    # Validate test_type
    case "${test_type}" in
        transport|hole-punch|perf)
            ;;
        *)
            echo "Error: Unknown test type: ${test_type}" >&2
            return 1
            ;;
    esac

    # Validate section
    case "${section}" in
        implementations|baselines|relays|routers)
            ;;
        *)
            echo "Error: Unknown section: ${section}" >&2
            return 1
            ;;
    esac

    echo "${test_type}-${section}-${id}"
}
