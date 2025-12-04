#!/bin/bash
# Generate results.md dashboard from results.yaml for transport interop tests

set -euo pipefail

# Use TEST_PASS_DIR if set, otherwise use current directory
RESULTS_FILE="${TEST_PASS_DIR:-.}/results.yaml"
OUTPUT_FILE="${TEST_PASS_DIR:-.}/results.md"

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

# Declare associative arrays for fast lookups in matrix generation
declare -A test_status_map
declare -A test_secure_map
declare -A test_muxer_map

# Only process tests if there are any
if [ "$test_count" -gt 0 ]; then
    # Export all test data as TSV in one yq call (much faster than individual calls)
    test_data=$(yq eval '.tests[] | [.name, .status, .dialer, .listener, .transport, .secureChannel, .muxer, .duration, .handshakePlusOneRTTMs // "", .pingRTTMs // ""] | @tsv' "$RESULTS_FILE")

    # Process each test and build both the table and hash maps
    while IFS=$'\t' read -r name status dialer listener transport secure muxer test_duration handshake_ms ping_ms; do

        # Store in hash maps for later matrix lookup
        test_status_map["$name"]="$status"
        test_secure_map["$name"]="$secure"
        test_muxer_map["$name"]="$muxer"

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
done <<< "$test_data"
fi

# Only generate matrix view if there are tests
if [ "$test_count" -gt 0 ]; then
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
            result=""

            # Try all possible secure/muxer combinations using hash map lookups (O(1) instead of O(n))
            # This is much faster than searching through all tests linearly
            for secure in "tls" "noise" "plaintext" "null"; do
                for muxer in "yamux" "mplex" "null"; do
                    # Construct test name based on whether it's standalone
                    if [ "$secure" = "null" ] || [ "$muxer" = "null" ]; then
                        test_name="$dialer x $listener ($transport)"
                    else
                        test_name="$dialer x $listener ($transport, $secure, $muxer)"
                    fi

                    # O(1) hash map lookup instead of O(n) linear search
                    if [ -n "${test_status_map[$test_name]:-}" ]; then
                        test_status="${test_status_map[$test_name]}"
                        test_secure="${test_secure_map[$test_name]}"
                        test_muxer="${test_muxer_map[$test_name]}"

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
fi

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

echo "  ✓ Generated "$OUTPUT_FILE""

# Generate HTML if pandoc is available
if command -v pandoc &> /dev/null; then
    HTML_FILE="${TEST_PASS_DIR:-.}/results.html"
    pandoc -f markdown -t html -s -o "$HTML_FILE" "$OUTPUT_FILE" \
        --metadata title="Transport Interop Results" \
        --css style.css 2>/dev/null || pandoc -f markdown -t html -s -o "$HTML_FILE" "$OUTPUT_FILE"
    echo "  ✓ Generated $HTML_FILE"
else
    echo "  ✗ pandoc not found, skipping HTML generation"
fi
