#!/usr/bin/env bash
# Test script to debug relay/router filtering

set -euo pipefail

# Simulate the pattern arrays
declare -a RELAY_IGNORE_PATTERNS=("linux")

# Copy the relay_should_ignore function
relay_should_ignore() {
    local relay_id="$1"

    # If no relay ignore patterns, don't ignore
    [ ${#RELAY_IGNORE_PATTERNS[@]} -eq 0 ] && return 1

    # Check if relay matches any ignore pattern
    for pattern in "${RELAY_IGNORE_PATTERNS[@]}"; do
        # Support inverted patterns with '!'
        case "$pattern" in
            !*)
                inverted_pattern="${pattern:1}"  # Remove '!' prefix
                case "$relay_id" in
                    *"$inverted_pattern"*)
                        # Match found, skip
                        ;;
                    *)
                        return 0  # Ignore (doesn't match inverted pattern)
                        ;;
                esac
                ;;
            *)
                # Normal pattern - ignore if matches
                case "$relay_id" in
                    *"$pattern"*)
                        return 0  # Ignore this relay
                        ;;
                esac
                ;;
        esac
    done

    return 1  # No ignore match
}

# Test
relay_id="linux"
echo "Testing relay_id='$relay_id' with RELAY_IGNORE_PATTERNS=('linux')"

if relay_should_ignore "$relay_id"; then
    echo "✓ relay_should_ignore returned TRUE (0) - relay WILL be ignored"
else
    echo "✗ relay_should_ignore returned FALSE (1) - relay will NOT be ignored"
fi

# Test the loop logic
echo ""
echo "Testing loop logic:"
relay_ids=("linux")
for relay_id in "${relay_ids[@]}"; do
    echo "  Processing relay: $relay_id"
    if relay_should_ignore "$relay_id"; then
        echo "  → Skipping (relay_should_ignore returned true)"
        continue
    fi
    echo "  → NOT skipped (would generate tests)"
done
