#!/bin/bash
# Common filter engine for test/baseline/relay/router filtering
# Provides recursive alias expansion with loop detection, proper inversion, and deduplication

# NOTE: This library requires ALIASES associative array to be loaded
# Source lib-test-aliases.sh and call load_aliases() before using these functions

# Internal: Recursively expand a single alias with loop detection
# Args:
#   $1: alias_name - The alias to expand
#   $2: processed_aliases - Space-separated list of already-processed aliases (for loop detection)
# Returns:
#   Expanded value (pipe-separated) or empty string
#   Returns 1 on error (circular reference)
_expand_alias_recursive() {
    local alias_name="$1"
    local processed_aliases="${2:-}"

    # Check for circular reference
    if [[ " $processed_aliases " == *" $alias_name "* ]]; then
        echo "ERROR: Circular alias reference detected in chain: $processed_aliases -> $alias_name" >&2
        return 1
    fi

    # Add current alias to processed set
    local new_processed="$processed_aliases $alias_name"

    # Get alias value from global ALIASES array
    local alias_value="${ALIASES[$alias_name]:-}"
    if [ -z "$alias_value" ]; then
        # Unknown alias - return empty (not an error, just undefined)
        echo ""
        return 0
    fi

    # Recursively expand any nested aliases in the value
    local result=""
    IFS='|' read -ra parts <<< "$alias_value"

    for part in "${parts[@]}"; do
        # Skip empty parts
        [ -z "$part" ] && continue

        if [[ "$part" =~ ^~(.+)$ ]]; then
            # Nested alias reference - recurse
            local nested_alias="${BASH_REMATCH[1]}"
            local expanded
            expanded=$(_expand_alias_recursive "$nested_alias" "$new_processed") || return 1

            if [ -n "$expanded" ]; then
                if [ -z "$result" ]; then
                    result="$expanded"
                else
                    result="$result|$expanded"
                fi
            fi
        else
            # Plain value - add as-is
            if [ -z "$result" ]; then
                result="$part"
            else
                result="$result|$part"
            fi
        fi
    done

    echo "$result"
}

# Internal: Invert a single substring (toggle ! prefix)
# Args:
#   $1: substring - The substring to invert
# Returns:
#   Inverted substring
_invert_substring() {
    local substring="$1"

    if [[ "$substring" =~ ^!(.+)$ ]]; then
        # Already has ! prefix - remove it
        echo "${BASH_REMATCH[1]}"
    else
        # Add ! prefix
        echo "!$substring"
    fi
}

# Deduplicate a pipe-separated filter string
# Args:
#   $1: filter_string - Pipe-separated string (may have duplicates)
# Returns:
#   Deduplicated, sorted pipe-separated string
deduplicate_filter() {
    local filter_string="$1"

    [ -z "$filter_string" ] && return 0

    # Split by |, sort, unique, rejoin
    echo "$filter_string" | tr '|' '\n' | grep -v '^$' | sort -u | paste -sd'|'
}

# Expand a full filter string with recursive alias expansion, inversion, and deduplication
# Args:
#   $1: filter_string - Raw filter string (e.g., "rust|!go|~stable|!~failing")
#   $2: all_names_array - Name of array variable containing all possible names (for negation expansion)
# Returns:
#   Fully expanded, deduplicated pipe-separated string
# Usage:
#   all_impls=("rust-v0.56" "go-v0.45" "python-v0.4")
#   result=$(expand_filter_string "~rust|!go" all_impls)
expand_filter_string() {
    local filter_string="$1"
    local -n all_names_ref=$2  # Name reference to array

    # Empty filter returns empty
    [ -z "$filter_string" ] && return 0

    local result_parts=()
    IFS='|' read -ra parts <<< "$filter_string"

    for part in "${parts[@]}"; do
        # Skip empty parts
        [ -z "$part" ] && continue

        # Remove shell escaping from ! if present
        part="${part#\\}"

        if [[ "$part" =~ ^!~(.+)$ ]]; then
            # Inverted alias: !~alias
            # Step 1: Recursively expand the alias
            local alias_name="${BASH_REMATCH[1]}"
            local expanded
            expanded=$(_expand_alias_recursive "$alias_name" "") || return 1

            # Step 2: Expand to all names that DON'T match ANY of the expanded patterns
            # This means: if name matches ANY pattern in the expansion, exclude it
            if [ -n "$expanded" ]; then
                IFS='|' read -ra expanded_patterns <<< "$expanded"

                # For each name in all_names, check if it matches any expanded pattern
                for name in "${all_names_ref[@]}"; do
                    local matches_any=false
                    for pattern in "${expanded_patterns[@]}"; do
                        if [[ "$name" == *"$pattern"* ]]; then
                            matches_any=true
                            break
                        fi
                    done

                    # If name does NOT match any pattern, include it
                    if [ "$matches_any" = false ]; then
                        result_parts+=("$name")
                    fi
                done
            fi

        elif [[ "$part" =~ ^~(.+)$ ]]; then
            # Regular alias: ~alias
            local alias_name="${BASH_REMATCH[1]}"
            local expanded
            expanded=$(_expand_alias_recursive "$alias_name" "") || return 1

            # Add all expanded parts
            if [ -n "$expanded" ]; then
                IFS='|' read -ra expanded_parts <<< "$expanded"
                result_parts+=("${expanded_parts[@]}")
            fi

        elif [[ "$part" =~ ^!(.+)$ ]]; then
            # Inverted value: !pattern
            # Expand to all names that DON'T contain the pattern
            local pattern="${BASH_REMATCH[1]}"

            for name in "${all_names_ref[@]}"; do
                if [[ "$name" != *"$pattern"* ]]; then
                    result_parts+=("$name")
                fi
            done

        else
            # Regular value: pattern
            result_parts+=("$part")
        fi
    done

    # Deduplicate and join
    if [ ${#result_parts[@]} -eq 0 ]; then
        echo ""
    else
        printf '%s\n' "${result_parts[@]}" | sort -u | paste -sd'|'
    fi
}

# Generic matching: check if a name matches any pattern in a filter string
# Args:
#   $1: name - The name to check
#   $2: filter_string - Pipe-separated filter (already expanded, no aliases)
# Returns:
#   0 (true) if name matches any pattern, 1 (false) otherwise
# Usage:
#   filter_matches "rust-v0.56" "rust|go" && echo "matches"
filter_matches() {
    local name="$1"
    local filter_string="$2"

    # Empty filter matches nothing (return false)
    [ -z "$filter_string" ] && return 1

    IFS='|' read -ra patterns <<< "$filter_string"
    for pattern in "${patterns[@]}"; do
        [ -z "$pattern" ] && continue
        [[ "$name" == *"$pattern"* ]] && return 0
    done

    return 1
}

# Generic filtering: filter a list of names using select and ignore filters
# Implements the two-step pattern:
#   1. Apply select filter to get selected_set
#   2. Apply ignore filter to selected_set to get final_set
#
# Args:
#   $1: input_names_array - Name of array variable with names to filter
#   $2: all_names_array - Name of array variable with ALL possible names (for negation)
#   $3: select_filter - Raw select filter (may contain aliases, inversions)
#   $4: ignore_filter - Raw ignore filter (may contain aliases, inversions)
# Returns:
#   Filtered names, one per line
# Usage:
#   all_impls=("rust-v0.56" "rust-v0.55" "go-v0.45")
#   input_impls=("${all_impls[@]}")
#   filtered=$(filter_names input_impls all_impls "~rust" "v0.56")
#   # Returns: rust-v0.55
filter_names() {
    local -n input_names_ref=$1
    local -n all_names_ref=$2
    local select_filter="$3"
    local ignore_filter="$4"

    # Step 1: Apply SELECT filter
    local selected=()

    if [ -z "$select_filter" ]; then
        # No select filter = include all input names
        selected=("${input_names_ref[@]}")
    else
        # Expand select filter
        local expanded_select
        expanded_select=$(expand_filter_string "$select_filter" all_names_ref) || return 1

        # Filter input names to those matching select
        for name in "${input_names_ref[@]}"; do
            if filter_matches "$name" "$expanded_select"; then
                selected+=("$name")
            fi
        done
    fi

    # Step 2: Apply IGNORE filter to the selected set (not to all names!)
    local final=()

    if [ -z "$ignore_filter" ]; then
        # No ignore filter = keep all selected
        final=("${selected[@]}")
    else
        # Expand ignore filter
        local expanded_ignore
        expanded_ignore=$(expand_filter_string "$ignore_filter" all_names_ref) || return 1

        # Remove names that match ignore from selected set
        for name in "${selected[@]}"; do
            if ! filter_matches "$name" "$expanded_ignore"; then
                final+=("$name")
            fi
        done
    fi

    # Return filtered names, one per line
    printf '%s\n' "${final[@]}"
}

# Generic entity filtering: filter entities by ID using select and ignore
# This is a convenience wrapper around filter_names for common use case
#
# Args:
#   $1: entity_ids_array - Name of array with entity IDs to filter
#   $2: all_entity_ids_array - Name of array with ALL entity IDs
#   $3: select_filter - Raw select filter
#   $4: ignore_filter - Raw ignore filter
# Returns:
#   Filtered entity IDs, one per line
# Usage:
#   all_relays=("linux" "chromium" "firefox")
#   relay_ids=("${all_relays[@]}")
#   filtered=$(filter_entities relay_ids all_relays "~linux" "")
filter_entities() {
    filter_names "$@"
}

# Debug helper: Print expansion steps (useful for troubleshooting)
# Args:
#   $1: filter_string - Filter to expand
#   $2: all_names_array - Name of array with all possible names
# Returns:
#   Prints debug info to stderr
debug_filter_expansion() {
    local filter_string="$1"
    local -n all_names_ref=$2

    echo "DEBUG: Expanding filter: '$filter_string'" >&2
    echo "DEBUG: All names: ${all_names_ref[*]}" >&2

    local result
    result=$(expand_filter_string "$filter_string" all_names_ref)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "DEBUG: Expanded to: '$result'" >&2
    else
        echo "DEBUG: Expansion failed with exit code $exit_code" >&2
    fi

    echo "$result"
    return $exit_code
}
