#!/bin/bash
# Generate results.md dashboard from results.yaml

set -euo pipefail

if [ ! -f results.yaml ]; then
    echo "Error: results.yaml not found"
    exit 1
fi

echo "Generating results dashboard..."

# Extract metadata
test_pass=$(yq eval '.metadata.testPass' results.yaml)
started_at=$(yq eval '.metadata.startedAt' results.yaml)
completed_at=$(yq eval '.metadata.completedAt' results.yaml)
duration=$(yq eval '.metadata.duration' results.yaml)
platform=$(yq eval '.metadata.platform' results.yaml)
os_name=$(yq eval '.metadata.os' results.yaml)
worker_count=$(yq eval '.metadata.workerCount' results.yaml)

# Extract summary
total=$(yq eval '.summary.total' results.yaml)
passed=$(yq eval '.summary.passed' results.yaml)
failed=$(yq eval '.summary.failed' results.yaml)

# Calculate pass rate
if [ "$total" -gt 0 ]; then
    pass_rate=$(awk "BEGIN {printf \"%.1f\", ($passed / $total) * 100}")
else
    pass_rate="0.0"
fi

# Generate markdown
cat > results.md <<EOF
# Hole Punch Interoperability Test Results

## Test Pass: \`$test_pass\`

**Summary:**
- **Total Tests:** $total
- **Passed:** ✅ $passed
- **Failed:** ❌ $failed
- **Pass Rate:** ${pass_rate}%

**Environment:**
- **Platform:** $platform
- **OS:** $os_name
- **Workers:** $worker_count
- **Duration:** $duration

**Timestamps:**
- **Started:** $started_at
- **Completed:** $completed_at

---

## Test Results

| Test | Dialer | Listener | Transport | Status | Duration |
|------|--------|----------|-----------|--------|----------|
EOF

# Read test results
test_count=$(yq eval '.tests | length' results.yaml)

for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".tests[$i].name" results.yaml)
    status=$(yq eval ".tests[$i].status" results.yaml)
    dialer=$(yq eval ".tests[$i].dialer" results.yaml)
    listener=$(yq eval ".tests[$i].listener" results.yaml)
    transport=$(yq eval ".tests[$i].transport" results.yaml)
    test_duration=$(yq eval ".tests[$i].duration" results.yaml)

    # Status icon
    if [ "$status" = "pass" ]; then
        status_icon="✅"
    else
        status_icon="❌"
    fi

    echo "| $name | $dialer | $listener | $transport | $status_icon | $test_duration |" >> results.md
done

cat >> results.md <<EOF

---

## Matrix View

EOF

# Generate matrix view (dialer x listener grid)
# Get unique dialers and listeners
dialers=$(yq eval '.tests[].dialer' results.yaml | sort -u)
listeners=$(yq eval '.tests[].listener' results.yaml | sort -u)

# Create header row
echo -n "| Dialer \\ Listener |" >> results.md
for listener in $listeners; do
    echo -n " $listener |" >> results.md
done
echo "" >> results.md

# Create separator row
echo -n "|---|" >> results.md
for listener in $listeners; do
    echo -n "---|" >> results.md
done
echo "" >> results.md

# Create data rows
for dialer in $dialers; do
    echo -n "| **$dialer** |" >> results.md

    for listener in $listeners; do
        # Find tests for this combination
        result=""

        for ((i=0; i<test_count; i++)); do
            test_dialer=$(yq eval ".tests[$i].dialer" results.yaml)
            test_listener=$(yq eval ".tests[$i].listener" results.yaml)
            test_status=$(yq eval ".tests[$i].status" results.yaml)
            test_transport=$(yq eval ".tests[$i].transport" results.yaml)

            if [ "$test_dialer" = "$dialer" ] && [ "$test_listener" = "$listener" ]; then
                if [ "$test_status" = "pass" ]; then
                    result="${result}✅"
                else
                    result="${result}❌"
                fi
                result="${result} ${transport} "
            fi
        done

        if [ -z "$result" ]; then
            result="-"
        fi

        echo -n " $result |" >> results.md
    done
    echo "" >> results.md
done

cat >> results.md <<EOF

---

## Legend

- ✅ Test passed
- ❌ Test failed
- Transport types: tcp, quic

---

*Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

echo "✓ Generated results.md"

# Generate HTML if pandoc is available
if command -v pandoc &> /dev/null; then
    echo "Generating HTML report..."
    pandoc -f markdown -t html -s -o results.html results.md \
        --metadata title="Hole Punch Interop Results" \
        --css style.css 2>/dev/null || pandoc -f markdown -t html -s -o results.html results.md
    echo "✓ Generated results.html"
else
    echo "→ pandoc not found, skipping HTML generation"
fi
