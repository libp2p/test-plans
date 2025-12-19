#!/bin/bash
# Alias loading from images.yaml
#
# NOTE: Alias expansion is in lib-filter-engine.sh (expand_filter_string)
# This file only loads aliases into the ALIASES array and provides entity ID retrieval

# Load aliases from images.yaml into an associative array
# This populates the global ALIASES array used by filter functions
#
# Args:
#   $1: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Populates global ALIASES associative array
# Usage:
#   load_aliases
#   load_aliases "custom-images.yaml"
load_aliases() {
    local images_file="${1:-images.yaml}"
    declare -gA ALIASES  # Global associative array

    if [ ! -f "$images_file" ]; then
        return
    fi

    # Check if test-aliases exists
    local alias_count=$(yq eval '.test-aliases | length' "$images_file" 2>/dev/null || echo 0)

    if [ "$alias_count" -eq 0 ] || [ "$alias_count" = "null" ]; then
        return
    fi

    # Load each alias
    for ((i=0; i<alias_count; i++)); do
        local alias_name=$(yq eval ".test-aliases[$i].alias" "$images_file")
        local alias_value=$(yq eval ".test-aliases[$i].value" "$images_file")
        ALIASES["$alias_name"]="$alias_value"
    done
}

# Generic function to get all entity IDs from images.yaml
# Works for any entity type: implementations, baselines, relays, routers, etc.
#
# Args:
#   $1: entity_type - Entity type key in images.yaml (e.g., "implementations", "baselines", "relays")
#   $2: images_file - Path to images.yaml (default: images.yaml)
# Returns:
#   Array of entity IDs (one per line)
# Usage:
#   all_impl_ids=($(get_entity_ids "implementations"))
#   all_baseline_ids=($(get_entity_ids "baselines"))
#   all_relay_ids=($(get_entity_ids "relays" "custom-images.yaml"))
get_entity_ids() {
    local entity_type="$1"
    local images_file="${2:-images.yaml}"

    if [ ! -f "$images_file" ]; then
        return 0
    fi

    yq eval ".${entity_type}[].id" "$images_file" 2>/dev/null || echo ""
}

# NOTE: The following functions have been REMOVED after migration to lib-filter-engine.sh:
# - get_all_impl_ids() - REMOVED: Use get_entity_ids("implementations") instead
# - expand_negated_alias() - REMOVED: Use expand_filter_string() from lib-filter-engine.sh
# - expand_aliases() - REMOVED: Use expand_filter_string() from lib-filter-engine.sh
#
# All test suites now use filter_names() or filter_entity_list() from lib-filter-engine.sh
