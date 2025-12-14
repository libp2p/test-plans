#!/bin/bash
# Common test filtering functions
# Used by both hole-punch and transport test generation

# Expand negation patterns to their logical set inversion
# e.g., !rust-v0.56 → go-v0.45|js-v3.x|... (all impls that don't match rust-v0.56)
expand_negations() {
    local pattern_string="$1"  # e.g., "!rust-v0.56|go-v0.45"
    local impls_yaml="${2:-impls.yaml}"

    # If no pattern, return empty
    [ -z "$pattern_string" ] && return 0

    # Get all implementation IDs
    local all_impls=$(yq eval '.implementations[].id' "$impls_yaml" | paste -sd'|')

    # Split pattern string by |
    IFS='|' read -ra patterns <<< "$pattern_string"

    local result=""

    for pattern in "${patterns[@]}"; do
        if [[ "$pattern" == !* ]] || [[ "$pattern" == \\!* ]]; then
            # Negation: expand to all impls that DON'T match
            local neg_pattern="${pattern#!}"
            neg_pattern="${neg_pattern#\\!}"

            # Get all impls that don't match this pattern
            IFS='|' read -ra all_impls_array <<< "$all_impls"
            for impl in "${all_impls_array[@]}"; do
                if [[ "$impl" != *"$neg_pattern"* ]]; then
                    result="$result|$impl"
                fi
            done
        else
            # Regular pattern: keep as-is
            result="$result|$pattern"
        fi
    done

    # Remove leading |
    result="${result#|}"

    # Deduplicate and sort
    result=$(echo "$result" | tr '|' '\n' | sort -u | paste -sd'|')

    echo "$result"
}

# Expand both aliases and negations, with deduplication
# This is the main expansion function that should be called
expand_all_patterns() {
    local pattern_string="$1"
    local impls_yaml="${2:-impls.yaml}"

    # If empty, return empty
    [ -z "$pattern_string" ] && return 0

    # First expand aliases (from lib-test-aliases.sh)
    local expanded=$(expand_aliases "$pattern_string")

    # Then expand negations
    expanded=$(expand_negations "$expanded" "$impls_yaml")

    echo "$expanded"
}

# Helper function to check if implementation ID matches select patterns
impl_matches_select() {
    local impl_id="$1"

    # No select = match all
    [ ${#SELECT_PATTERNS[@]} -eq 0 ] && return 0

    # Check each select pattern against implementation ID
    for select in "${SELECT_PATTERNS[@]}"; do
        [[ "$impl_id" == *"$select"* ]] && return 0
    done

    return 1
}

# Helper function to check if test name matches select
matches_select() {
    local test_name="$1"

    # No select = match all
    [ ${#SELECT_PATTERNS[@]} -eq 0 ] && return 0

    # Check each select pattern
    for select in "${SELECT_PATTERNS[@]}"; do
        [[ "$test_name" == *"$select"* ]] && return 0
    done

    return 1
}

# Helper function to check if test name should be ignored
should_ignore() {
    local test_name="$1"

    # No ignore patterns = don't ignore
    [ ${#IGNORE_PATTERNS[@]} -eq 0 ] && return 1

    # Check each ignore pattern
    for ignore in "${IGNORE_PATTERNS[@]}"; do
        # Check if pattern starts with ! or \! (negation - handle shell escaping)
        if [[ "$ignore" == !* ]] || [[ "$ignore" == \\!* ]]; then
            # Negation: ignore if EITHER dialer OR listener does NOT contain the pattern
            # This ensures only tests where BOTH contain the pattern are kept
            local pattern="${ignore#!}"    # Remove leading !
            pattern="${pattern#\\!}"       # Remove leading \! if escaped

            # Extract dialer and listener from test name: "dialer x listener (...)"
            local dialer=$(echo "$test_name" | sed 's/ x .*//')
            local listener=$(echo "$test_name" | sed 's/.* x //' | sed 's/ (.*//')

            # Ignore if either dialer or listener doesn't contain the pattern
            if [[ "$dialer" != *"$pattern"* ]] || [[ "$listener" != *"$pattern"* ]]; then
                return 0  # Ignore because at least one side doesn't match
            fi
        else
            # Normal: ignore if test name DOES contain the pattern
            if [[ "$test_name" == *"$ignore"* ]]; then
                return 0  # Ignore because it matches
            fi
        fi
    done

    return 1  # Don't ignore
}

# Get common elements between two space-separated lists
get_common() {
    local list1="$1"
    local list2="$2"
    local result=""

    for item in $list1; do
        if [[ " $list2 " == *" $item "* ]]; then
            result="$result $item"
        fi
    done

    echo "$result"
}
