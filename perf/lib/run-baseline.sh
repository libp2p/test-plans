#!/bin/bash
# Run baseline performance tests
# Uses same test format and logic as main perf tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"
source "lib/lib-perf.sh"

# Check if test matrix exists
if [ ! -f "$TEST_PASS_DIR/test-matrix.yaml" ]; then
    echo "  ✗ Test matrix not found"
    exit 1
fi

# Get baseline test count
baseline_count=$(yq eval '.baselines | length' "$TEST_PASS_DIR/test-matrix.yaml" 2>/dev/null || echo "0")

if [ "$baseline_count" -eq 0 ]; then
    echo "  → No baseline tests selected"
    exit 0
fi

echo ""
print_header "Running baseline tests... (1 worker)"

# Initialize baseline results file
> "$TEST_PASS_DIR/baseline-results.yaml.tmp"

for ((i=0; i<baseline_count; i++)); do
    baseline_name=$(yq eval ".baselines[$i].name" "$TEST_PASS_DIR/test-matrix.yaml")

    # Show progress (same format as main tests)
    echo "[$((i + 1))/$baseline_count] $baseline_name"

    # Run baseline test using same script, passing "baseline" as test type
    bash lib/run-single-test.sh "$i" "baseline" >/dev/null 2>&1 || {
        echo "  ✗ Baseline test $i failed"
        # Continue with other baseline tests
    }
done

exit 0
