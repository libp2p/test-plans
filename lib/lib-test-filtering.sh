#!/bin/bash
# Common utility functions for test generation
#
# NOTE: Entity filtering functions are in lib-filter-engine.sh
# Use filter_names() or filter_entity_list() for all filtering operations
# This file contains only generic utility functions

# Get common elements between two space-separated lists
# This is a generic set intersection operation
#
# Args:
#   $1: list1 - First space-separated list
#   $2: list2 - Second space-separated list
# Returns:
#   Space-separated list of common elements
# Usage:
#   common=$(get_common "tcp ws quic" "tcp quic webrtc")
#   # Returns: "tcp quic"
get_common() {
    local list1="$1"
    local list2="$2"
    local result=""

    for item in ${list1}; do
        case " ${list2} " in
            *" ${item} "*)
                result="${result} ${item}"
                ;;
        esac
    done

    echo "${result}"
}
