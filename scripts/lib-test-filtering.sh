#!/bin/bash
# Common test filtering functions
# Used by both hole-punch and transport test generation

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
        [[ "$test_name" == *"$ignore"* ]] && return 0
    done

    return 1
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
