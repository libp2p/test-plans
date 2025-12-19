#!/bin/bash
# Common test filtering functions
# Used by both hole-punch and transport test generation

# NOTE: Legacy expand_negations() and expand_all_patterns() functions have been
# removed and replaced by expand_filter_string() from lib-filter-engine.sh which
# provides recursive alias expansion, loop detection, and correct inversion handling.

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

# NOTE: The functions impl_matches_select(), matches_select(), and should_ignore()
# still work with the new filter engine. They expect pre-expanded filter strings.
#
# For new code, it's recommended to:
# 1. Source lib-filter-engine.sh
# 2. Use expand_filter_string() for expansion (handles recursion, loops, inversions)
# 3. Use filter_names() for complete two-step select/ignore filtering
# 4. Use filter_matches() as a generic replacement for entity-specific matching
#
# Migration example:
#   OLD: TEST_SELECT=$(expand_aliases "$TEST_SELECT")
#        impl_matches_select "$impl_id"
#
#   NEW: all_impls=($(yq eval '.implementations[].id' images.yaml))
#        TEST_SELECT=$(expand_filter_string "$TEST_SELECT" all_impls)
#        filter_matches "$impl_id" "$TEST_SELECT"
