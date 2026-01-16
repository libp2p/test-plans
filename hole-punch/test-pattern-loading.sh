#!/bin/bash
# Test how patterns are loaded from CLI arguments

set -euo pipefail

# Simulate CLI arguments like generate-tests.sh receives them
CLI_TEST_SELECT=""
CLI_TEST_IGNORE=""
CLI_RELAY_SELECT=""
CLI_RELAY_IGNORE="linux"
CLI_ROUTER_SELECT=""
CLI_ROUTER_IGNORE=""
DEBUG="false"

# Set variables like generate-tests.sh does
TEST_SELECT="$CLI_TEST_SELECT"
TEST_IGNORE="$CLI_TEST_IGNORE"
RELAY_SELECT="$CLI_RELAY_SELECT"
RELAY_IGNORE="$CLI_RELAY_IGNORE"
ROUTER_SELECT="$CLI_ROUTER_SELECT"
ROUTER_IGNORE="$CLI_ROUTER_IGNORE"

echo "Input variables:"
echo "  RELAY_IGNORE='$RELAY_IGNORE'"
echo ""

# Load patterns like generate-tests.sh does
declare -a RELAY_IGNORE_PATTERNS=()

if [ -n "$RELAY_IGNORE" ]; then
    IFS='|' read -ra RELAY_IGNORE_PATTERNS <<< "$RELAY_IGNORE"
    echo "Loaded ${#RELAY_IGNORE_PATTERNS[@]} relay ignore pattern(s):"
    for pattern in "${RELAY_IGNORE_PATTERNS[@]}"; do
        echo "  - '$pattern'"
    done
else
    echo "No RELAY_IGNORE patterns"
fi

echo ""
echo "Testing pattern matching:"
relay_id="linux"
echo "  Checking if '$relay_id' matches pattern 'linux'..."
case "$relay_id" in
    *"linux"*)
        echo "  ✓ Match!"
        ;;
    *)
        echo "  ✗ No match"
        ;;
esac
