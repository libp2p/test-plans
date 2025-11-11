#!/bin/bash
# Generate results.md dashboard from results.yaml for transport interop tests

set -euo pipefail

# Use TEST_PASS_DIR if set, otherwise use current directory
RESULTS_FILE="${TEST_PASS_DIR:-.}/results.yaml"
OUTPUT_FILE="${TEST_PASS_DIR:-.}/results.md"

if [ ! -f "$RESULTS_FILE" ]; then
    echo "Error: $RESULTS_FILE not found"
    exit 1
fi

echo "Generating results dashboard..."

# Extract metadata
test_pass=$(yq eval '.metadata.testPass' "$RESULTS_FILE")
started_at=$(yq eval '.metadata.startedAt' "$RESULTS_FILE")
completed_at=$(yq eval '.metadata.completedAt' "$RESULTS_FILE")
duration=$(yq eval '.metadata.duration' "$RESULTS_FILE")
platform=$(yq eval '.metadata.platform' "$RESULTS_FILE")
os_name=$(yq eval '.metadata.os' "$RESULTS_FILE")
worker_count=$(yq eval '.metadata.workerCount' "$RESULTS_FILE")

# Extract summary
total=$(yq eval '.summary.total' "$RESULTS_FILE")
passed=$(yq eval '.summary.passed' "$RESULTS_FILE")
failed=$(yq eval '.summary.failed' "$RESULTS_FILE")

# Calculate pass rate
if [ "$total" -gt 0 ]; then
    pass_rate=$(awk "BEGIN {printf \"%.1f\", ($passed / $total) * 100}")
else
    pass_rate="0.0"
fi

# Generate markdown
cat > "$OUTPUT_FILE" <<EOF
# Transport Interoperability Test Results

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

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
EOF

# Read test results
test_count=$(yq eval '.tests | length' "$RESULTS_FILE")

for ((i=0; i<test_count; i++)); do
    name=$(yq eval ".tests[$i].name" "$RESULTS_FILE")
    status=$(yq eval ".tests[$i].status" "$RESULTS_FILE")
    dialer=$(yq eval ".tests[$i].dialer" "$RESULTS_FILE")
    listener=$(yq eval ".tests[$i].listener" "$RESULTS_FILE")
    transport=$(yq eval ".tests[$i].transport" "$RESULTS_FILE")
    secure=$(yq eval ".tests[$i].secureChannel" "$RESULTS_FILE")
    muxer=$(yq eval ".tests[$i].muxer" "$RESULTS_FILE")
    test_duration=$(yq eval ".tests[$i].duration" "$RESULTS_FILE")
    handshake_ms=$(yq eval ".tests[$i].handshakePlusOneRTTMs" "$RESULTS_FILE" 2>/dev/null)
    ping_ms=$(yq eval ".tests[$i].pingRTTMs" "$RESULTS_FILE" 2>/dev/null)

    # Status icon
    if [ "$status" = "pass" ]; then
        status_icon="✅"
    else
        status_icon="❌"
    fi

    # Handle null values for standalone transports
    [ "$secure" = "null" ] && secure="-"
    [ "$muxer" = "null" ] && muxer="-"

    # Handle null/missing metrics
    [ "$handshake_ms" = "null" ] || [ -z "$handshake_ms" ] && handshake_ms="-"
    [ "$ping_ms" = "null" ] || [ -z "$ping_ms" ] && ping_ms="-"

    echo "| $name | $dialer | $listener | $transport | $secure | $muxer | $status_icon | $test_duration | $handshake_ms | $ping_ms |" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## Matrix View by Transport

EOF

# Generate matrix view grouped by transport
transports=$(yq eval '.tests[].transport' "$RESULTS_FILE" | sort -u)

for transport in $transports; do
    echo "### Transport: $transport" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Get unique dialers and listeners for this transport
    dialers=$(yq eval ".tests[] | select(.transport == \"$transport\") | .dialer" "$RESULTS_FILE" | sort -u)
    listeners=$(yq eval ".tests[] | select(.transport == \"$transport\") | .listener" "$RESULTS_FILE" | sort -u)

    # Create header row
    echo -n "| Dialer \\ Listener |" >> "$OUTPUT_FILE"
    for listener in $listeners; do
        echo -n " $listener |" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"

    # Create separator row
    echo -n "|---|" >> "$OUTPUT_FILE"
    for listener in $listeners; do
        echo -n "---|" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"

    # Create data rows
    for dialer in $dialers; do
        echo -n "| **$dialer** |" >> "$OUTPUT_FILE"

        for listener in $listeners; do
            # Find tests for this combination
            result=""

            for ((i=0; i<test_count; i++)); do
                test_dialer=$(yq eval ".tests[$i].dialer" "$RESULTS_FILE")
                test_listener=$(yq eval ".tests[$i].listener" "$RESULTS_FILE")
                test_status=$(yq eval ".tests[$i].status" "$RESULTS_FILE")
                test_transport=$(yq eval ".tests[$i].transport" "$RESULTS_FILE")
                test_secure=$(yq eval ".tests[$i].secureChannel" "$RESULTS_FILE")
                test_muxer=$(yq eval ".tests[$i].muxer" "$RESULTS_FILE")

                if [ "$test_dialer" = "$dialer" ] && \
                   [ "$test_listener" = "$listener" ] && \
                   [ "$test_transport" = "$transport" ]; then

                    if [ "$test_status" = "pass" ]; then
                        icon="✅"
                    else
                        icon="❌"
                    fi

                    # For standalone transports, just show icon
                    if [ "$test_secure" = "null" ] || [ "$test_muxer" = "null" ]; then
                        result="${result}${icon} "
                    else
                        # Show secure/muxer combo
                        result="${result}${icon}${test_secure:0:1}/${test_muxer:0:1} "
                    fi
                fi
            done

            if [ -z "$result" ]; then
                result="-"
            fi

            echo -n " $result |" >> "$OUTPUT_FILE"
        done
        echo "" >> "$OUTPUT_FILE"
    done

    echo "" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## Legend

- ✅ Test passed
- ❌ Test failed
- **n/y** = noise/yamux, **t/m** = tls/mplex, etc.
- Transports: tcp, ws, quic-v1, webrtc-direct, webtransport
- Secure channels: noise (n), tls (t), plaintext (p)
- Muxers: yamux (y), mplex (m)

---

*Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)*
EOF

echo "✓ Generated "$OUTPUT_FILE""

# Generate HTML if pandoc is available
if command -v pandoc &> /dev/null; then
    echo "Generating HTML report..."
    HTML_FILE="${TEST_PASS_DIR:-.}/results.html"
    pandoc -f markdown -t html -s -o "$HTML_FILE" "$OUTPUT_FILE" \
        --metadata title="Transport Interop Results" \
        --css style.css 2>/dev/null || pandoc -f markdown -t html -s -o "$HTML_FILE" "$OUTPUT_FILE"
    echo "✓ Generated $HTML_FILE"
else
    echo "→ pandoc not found, skipping HTML generation"
fi
