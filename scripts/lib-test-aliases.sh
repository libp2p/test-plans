#!/bin/bash
# Common test alias expansion functions
# Used by both hole-punch and transport test generation

# Load aliases from impls.yaml into an associative array
load_aliases() {
    declare -gA ALIASES  # Global associative array

    if [ ! -f "impls.yaml" ]; then
        return
    fi

    # Check if test-aliases exists
    local alias_count=$(yq eval '.test-aliases | length' impls.yaml 2>/dev/null || echo 0)

    if [ "$alias_count" -eq 0 ] || [ "$alias_count" = "null" ]; then
        return
    fi

    # Load each alias
    for ((i=0; i<alias_count; i++)); do
        local alias_name=$(yq eval ".test-aliases[$i].alias" impls.yaml)
        local alias_value=$(yq eval ".test-aliases[$i].value" impls.yaml)
        ALIASES["$alias_name"]="$alias_value"
    done
}

# Get all implementation IDs as a pipe-separated string
get_all_impl_ids() {
    yq eval '.implementations[].id' impls.yaml | paste -sd'|' -
}

# Expand a single negated alias (!~alias)
# Returns the expanded value (all impl IDs that DON'T match the alias value)
expand_negated_alias() {
    local alias_name="$1"

    # Get the alias value
    if [ -z "${ALIASES[$alias_name]:-}" ]; then
        echo ""
        return
    fi

    local alias_value="${ALIASES[$alias_name]}"

    # Get all implementation IDs
    local all_impls=$(get_all_impl_ids)

    # Split alias value by | to get patterns to exclude
    IFS='|' read -ra EXCLUDE_PATTERNS <<< "$alias_value"

    # Split all impl IDs by |
    IFS='|' read -ra ALL_IDS <<< "$all_impls"

    # Filter: keep IDs that DON'T match any exclude pattern
    local result=""
    for impl_id in "${ALL_IDS[@]}"; do
        local should_exclude=false

        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            if [[ "$impl_id" == *"$pattern"* ]]; then
                should_exclude=true
                break
            fi
        done

        if [ "$should_exclude" = false ]; then
            if [ -z "$result" ]; then
                result="$impl_id"
            else
                result="$result|$impl_id"
            fi
        fi
    done

    echo "$result"
}

# Expand aliases in a test selection string
# Handles both ~alias and !~alias syntax
expand_aliases() {
    local input="$1"

    # If empty, return empty
    if [ -z "$input" ]; then
        echo ""
        return
    fi

    local result="$input"

    # Process negated aliases first (!~alias)
    while [[ "$result" =~ \!~([a-zA-Z0-9_-]+) ]]; do
        local alias_name="${BASH_REMATCH[1]}"
        local expanded=$(expand_negated_alias "$alias_name")

        if [ -n "$expanded" ]; then
            # Replace !~alias with expanded value
            result="${result//!~$alias_name/$expanded}"
        else
            # Unknown alias, remove it
            result="${result//!~$alias_name/}"
        fi
    done

    # Process regular aliases (~alias)
    while [[ "$result" =~ ~([a-zA-Z0-9_-]+) ]]; do
        local alias_name="${BASH_REMATCH[1]}"

        if [ -n "${ALIASES[$alias_name]:-}" ]; then
            local alias_value="${ALIASES[$alias_name]}"
            # Replace ~alias with its value
            result="${result//~$alias_name/$alias_value}"
        else
            # Unknown alias, remove it
            result="${result//~$alias_name/}"
        fi
    done

    # Clean up any double pipes or leading/trailing pipes
    result=$(echo "$result" | sed 's/||*/|/g' | sed 's/^|//; s/|$//')

    echo "$result"
}
