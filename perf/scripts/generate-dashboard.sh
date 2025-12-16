#!/bin/bash
# Generate results dashboard (MD, HTML) from results.yaml
# Matches transport/hole-punch dashboard generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Use TEST_PASS_DIR results.yaml (created by run_tests.sh)
RESULTS_FILE="${TEST_PASS_DIR}/results.yaml"
OUTPUT_MD="${TEST_PASS_DIR}/results.md"
OUTPUT_HTML="${TEST_PASS_DIR}/results.html"

if [ ! -f "$RESULTS_FILE" ]; then
    echo "✗ Error: $RESULTS_FILE not found"
    exit 1
fi

# Extract metadata
test_pass=$(yq eval '.metadata.testPass' "$RESULTS_FILE")
started_at=$(yq eval '.metadata.startedAt' "$RESULTS_FILE")
completed_at=$(yq eval '.metadata.completedAt' "$RESULTS_FILE")
duration=$(yq eval '.metadata.duration' "$RESULTS_FILE")
platform=$(yq eval '.metadata.platform' "$RESULTS_FILE")
os_name=$(yq eval '.metadata.os' "$RESULTS_FILE")

# Extract summary
total_baselines=$(yq eval '.summary.totalBaselines' "$RESULTS_FILE")
baselines_passed=$(yq eval '.summary.baselinesPassed' "$RESULTS_FILE")
baselines_failed=$(yq eval '.summary.baselinesFailed' "$RESULTS_FILE")
total_tests=$(yq eval '.summary.totalTests' "$RESULTS_FILE")
tests_passed=$(yq eval '.summary.testsPassed' "$RESULTS_FILE")
tests_failed=$(yq eval '.summary.testsFailed' "$RESULTS_FILE")
total_all=$(yq eval '.summary.totalAll' "$RESULTS_FILE")
passed_all=$(yq eval '.summary.passedAll' "$RESULTS_FILE")
failed_all=$(yq eval '.summary.failedAll' "$RESULTS_FILE")

# Calculate pass rate
if [ "$total_all" -gt 0 ]; then
    pass_rate=$(awk "BEGIN {printf \"%.1f\", ($passed_all / $total_all) * 100}")
else
    pass_rate="0.0"
fi

# Generate results.md
cat > "$OUTPUT_MD" <<EOF
# Performance Test Results

**Test Pass:** $test_pass
**Started:** $started_at
**Completed:** $completed_at
**Duration:** $duration
**Platform:** $platform ($os_name)

## Summary

- **Total Tests:** $total_all ($total_baselines baseline + $total_tests main)
- **Passed:** $passed_all (${pass_rate}%)
- **Failed:** $failed_all

### Baseline Results
- Total: $total_baselines
- Passed: $baselines_passed
- Failed: $baselines_failed

### Main Test Results
- Total: $total_tests
- Passed: $tests_passed
- Failed: $tests_failed

## Box Plot Statistics

### Upload Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
EOF

# Extract upload stats from each test
test_count=$(yq eval '.testResults | length' "$RESULTS_FILE" 2>/dev/null || echo "0")
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].upload.min" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q1=$(yq eval ".testResults[$i].upload.q1" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    median=$(yq eval ".testResults[$i].upload.median" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q3=$(yq eval ".testResults[$i].upload.q3" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    max=$(yq eval ".testResults[$i].upload.max" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    outlier_count=$(yq eval ".testResults[$i].upload.outliers | length" "$RESULTS_FILE" 2>/dev/null || echo "0")

    echo "| $name | $min | $q1 | $median | $q3 | $max | $outlier_count |" >> "$OUTPUT_MD"
done

cat >> "$OUTPUT_MD" <<'EOF'

### Download Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
EOF

# Extract download stats from each test
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].download.min" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q1=$(yq eval ".testResults[$i].download.q1" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    median=$(yq eval ".testResults[$i].download.median" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q3=$(yq eval ".testResults[$i].download.q3" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    max=$(yq eval ".testResults[$i].download.max" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    outlier_count=$(yq eval ".testResults[$i].download.outliers | length" "$RESULTS_FILE" 2>/dev/null || echo "0")

    echo "| $name | $min | $q1 | $median | $q3 | $max | $outlier_count |" >> "$OUTPUT_MD"
done

cat >> "$OUTPUT_MD" <<'EOF'

### Latency (seconds)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
EOF

# Extract latency stats from each test
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].latency.min" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q1=$(yq eval ".testResults[$i].latency.q1" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    median=$(yq eval ".testResults[$i].latency.median" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    q3=$(yq eval ".testResults[$i].latency.q3" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    max=$(yq eval ".testResults[$i].latency.max" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    outlier_count=$(yq eval ".testResults[$i].latency.outliers | length" "$RESULTS_FILE" 2>/dev/null || echo "0")

    echo "| $name | $min | $q1 | $median | $q3 | $max | $outlier_count |" >> "$OUTPUT_MD"
done

cat >> "$OUTPUT_MD" <<'EOF'

## Test Results

EOF

# Append baseline results
yq eval '.baselineResults[] | "### " + .name + "\n- Status: " + .status + "\n"' "$RESULTS_FILE" >> "$OUTPUT_MD" 2>/dev/null || true

# Append main test results
yq eval '.testResults[] | "### " + .name + "\n- Status: " + .status + "\n"' "$RESULTS_FILE" >> "$OUTPUT_MD" 2>/dev/null || true

# Generate simple HTML
cat > "$OUTPUT_HTML" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Performance Test Results - $test_pass</title>
    <style>
        body { font-family: monospace; margin: 20px; }
        .pass { color: green; }
        .fail { color: red; }
    </style>
</head>
<body>
    <h1>Performance Test Results</h1>
    <p><strong>Test Pass:</strong> $test_pass</p>
    <p><strong>Duration:</strong> $duration</p>
    <h2>Summary</h2>
    <ul>
        <li>Total: $total_all ($total_baselines baseline + $total_tests main)</li>
        <li class="pass">Passed: $passed_all</li>
        <li class="fail">Failed: $failed_all</li>
    </ul>
</body>
</html>
EOF

echo "  ✓ Generated $OUTPUT_MD"
echo "  ✓ Generated $OUTPUT_HTML"

exit 0
