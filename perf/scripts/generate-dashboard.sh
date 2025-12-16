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
LATEST_RESULTS_FILE="${TEST_PASS_DIR}/LATEST_TEST_RESULTS.md"

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

# Generate LATEST_TEST_RESULTS.md (detailed results with box plot statistics)
cat > "$LATEST_RESULTS_FILE" <<EOF
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

## Environment

- **Platform:** $platform
- **OS:** $os_name
- **Started:** $started_at
- **Completed:** $completed_at
- **Duration:** $duration

## Timestamps

- **Started:** $started_at
- **Completed:** $completed_at

---

## Box Plot Statistics

### Upload Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max |
|------|-----|-------|--------|-------|-----|
EOF

# Extract upload stats from each test (without Outliers column)
test_count=$(yq eval '.testResults | length' "$RESULTS_FILE" 2>/dev/null || echo "0")
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].upload.min" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q1=$(yq eval ".testResults[$i].upload.q1" "$RESULTS_FILE" 2>/dev/null || echo "null")
    median=$(yq eval ".testResults[$i].upload.median" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q3=$(yq eval ".testResults[$i].upload.q3" "$RESULTS_FILE" 2>/dev/null || echo "null")
    max=$(yq eval ".testResults[$i].upload.max" "$RESULTS_FILE" 2>/dev/null || echo "null")

    echo "| $name | $min | $q1 | $median | $q3 | $max |" >> "$LATEST_RESULTS_FILE"
done

cat >> "$LATEST_RESULTS_FILE" <<'EOF'

### Download Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max |
|------|-----|-------|--------|-------|-----|
EOF

# Extract download stats from each test (without Outliers column)
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].download.min" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q1=$(yq eval ".testResults[$i].download.q1" "$RESULTS_FILE" 2>/dev/null || echo "null")
    median=$(yq eval ".testResults[$i].download.median" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q3=$(yq eval ".testResults[$i].download.q3" "$RESULTS_FILE" 2>/dev/null || echo "null")
    max=$(yq eval ".testResults[$i].download.max" "$RESULTS_FILE" 2>/dev/null || echo "null")

    echo "| $name | $min | $q1 | $median | $q3 | $max |" >> "$LATEST_RESULTS_FILE"
done

cat >> "$LATEST_RESULTS_FILE" <<'EOF'

### Latency (seconds)

| Test | Min | Q1 | Median | Q3 | Max |
|------|-----|-------|--------|-------|-----|
EOF

# Extract latency stats from each test (without Outliers column)
for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".testResults[$i].name" "$RESULTS_FILE" 2>/dev/null || echo "N/A")
    min=$(yq eval ".testResults[$i].latency.min" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q1=$(yq eval ".testResults[$i].latency.q1" "$RESULTS_FILE" 2>/dev/null || echo "null")
    median=$(yq eval ".testResults[$i].latency.median" "$RESULTS_FILE" 2>/dev/null || echo "null")
    q3=$(yq eval ".testResults[$i].latency.q3" "$RESULTS_FILE" 2>/dev/null || echo "null")
    max=$(yq eval ".testResults[$i].latency.max" "$RESULTS_FILE" 2>/dev/null || echo "null")

    echo "| $name | $min | $q1 | $median | $q3 | $max |" >> "$LATEST_RESULTS_FILE"
done

cat >> "$LATEST_RESULTS_FILE" <<'EOF'

---

*Generated: EOF
date -u +%Y-%m-%dT%H:%M:%SZ >> "$LATEST_RESULTS_FILE"
echo "*" >> "$LATEST_RESULTS_FILE"

echo "  ✓ Generated $LATEST_RESULTS_FILE"

# Generate main results.md (with box plots)
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

### Main Test Results
- Total: $total_tests
- Passed: $tests_passed
- Failed: $tests_failed

### Baseline Results
- Total: $total_baselines
- Passed: $baselines_passed
- Failed: $baselines_failed

## Environment

- **Platform:** $platform
- **OS:** $os_name
- **Started:** $started_at
- **Completed:** $completed_at
- **Duration:** $duration

## Timestamps

- **Started:** $started_at
- **Completed:** $completed_at

---

## Latest Test Results

See [Latest Test Results](LATEST_TEST_RESULTS.md) for detailed statistics.

---

## Results

### Upload Throughput

![Upload Box Plot](upload_boxplot.png)

### Download Throughput

![Download Box Plot](download_boxplot.png)

### Latency

![Latency Box Plot](latency_boxplot.png)

---

*Generated: EOF
date -u +%Y-%m-%dT%H:%M:%SZ >> "$OUTPUT_MD"
echo "*" >> "$OUTPUT_MD"

echo "  ✓ Generated $OUTPUT_MD"

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
        img { max-width: 800px; margin: 20px 0; }
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
    <h2>Box Plots</h2>
    <h3>Upload Throughput</h3>
    <img src="upload_boxplot.png" alt="Upload Throughput">
    <h3>Download Throughput</h3>
    <img src="download_boxplot.png" alt="Download Throughput">
    <h3>Latency</h3>
    <img src="latency_boxplot.png" alt="Latency">
</body>
</html>
EOF

echo "  ✓ Generated $OUTPUT_HTML"

exit 0
