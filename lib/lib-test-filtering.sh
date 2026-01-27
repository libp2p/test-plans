#!/usr/bin/env bash
# Common utility functions for test generation
#
# NOTE: Entity filtering functions are in lib-filter-engine.sh
# Use filter_names() or filter_entity_list() for all filtering operations
# This file contains only generic utility functions

# Get common elements between any number of space-separated lists
# This is a generic set intersection operation using associative arrays
#
# Args:
#   $@: Any number of space-separated lists
# Returns:
#   Space-separated list of common elements (intersection of all input lists)
# Usage:
#   common=$(get_common "tcp ws quic" "tcp quic webrtc")
#   # Returns: "tcp quic"
#   common=$(get_common "tcp ws quic" "tcp quic" "tcp ws")
#   # Returns: "tcp ws"
get_common() {
    # If no arguments, return empty
    if [[ $# -eq 0 ]]; then
        echo ""
        return
    fi

    # If only one argument, return it as-is
    if [[ $# -eq 1 ]]; then
        echo "$1"
        return
    fi

    local -A item_map
    local result=""

    # Initialize with the first list
    local first_list="$1"
    for item in ${first_list}; do
        item_map["$item"]=1
    done
    shift

    # For each remaining list, keep only items that appear in it
    for list in "$@"; do
        local -A current_list_map

        # Build a map of items in current list
        for item in ${list}; do
            current_list_map["$item"]=1
        done

        # Remove items from item_map that are not in current list
        for item in "${!item_map[@]}"; do
            if [[ -z "${current_list_map[$item]:-}" ]]; then
                unset item_map["$item"]
            fi
        done

        # Early exit if no items left
        if [[ -z ${!item_map[@]} ]]; then
            echo ""
            return
        fi
    done

    # Build result from remaining items
    for item in "${!item_map[@]}"; do
        result="${result} ${item}"
    done

    echo "${result}"
}
