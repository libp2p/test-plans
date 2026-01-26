#!/usr/bin/env bash

# Generate results dashboard for JS-libp2p Echo interoperability tests
# Creates markdown and HTML dashboards from test results

set -euo pipefail

generate_results_dashboard() {
    local results_dir="${TEST_PASS_DIR}/results"
    local results_yaml="${TEST_PASS_DIR}/results.yaml"
    local results_md="${TEST_PASS_DIR}/results.md"
    local results_html="${TEST_PASS_DIR}/results.html"
    
    if [[ ! -d "$results_dir" ]]; then
        echo "No results directory found: $results_dir"
        return 1
    fi
    
    # Collect all individual result files
    local result_files=()
    while IFS= read -r -d '' file; do
        result_files+=("$file")
    done < <(find "$results_dir" -name "*.yaml" -print0 2>/dev/null || true)
    
    if [[ ${#result_files[@]} -eq 0 ]]; then
        echo "No result files found in $results_dir"
        return 1
    fi
    
    # Generate aggregated results.yaml
    generate_results_yaml "${result_files[@]}"
    
    # Generate markdown dashboard
    generate_results_markdown
    
    # Generate HTML dashboard
    generate_results_html
    
    echo "Results dashboard generated:"
    echo "  YAML: $results_yaml"
    echo "  Markdown: $results_md"
    echo "  HTML: $results_html"
}

generate_results_yaml() {
    local result_files=("$@")
    local results_yaml="${TEST_PASS_DIR}/results.yaml"
    
    local total=0
    local passed=0
    local failed=0
    local start_time=""
    local end_time=""
    
    # Calculate summary statistics
    for file in "${result_files[@]}"; do
        if [[ -f "$file" ]]; then
            local status
            status=$(yq eval '.status' "$file" 2>/dev/null || echo "unknown")
            
            total=$((total + 1))
            case "$status" in
                "passed"|"pass")
                    passed=$((passed + 1))
                    ;;
                "failed"|"fail")
                    failed=$((failed + 1))
                    ;;
            esac
            
            # Track time range
            local timestamp
            timestamp=$(yq eval '.timestamp' "$file" 2>/dev/null || echo "")
            if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
                if [[ -z "$start_time" || "$timestamp" < "$start_time" ]]; then
                    start_time="$timestamp"
                fi
                if [[ -z "$end_time" || "$timestamp" > "$end_time" ]]; then
                    end_time="$timestamp"
                fi
            fi
        fi
    done
    
    # Calculate duration
    local duration=0
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        local start_epoch end_epoch
        start_epoch=$(date -d "$start_time" +%s 2>/dev/null || echo "0")
        end_epoch=$(date -d "$end_time" +%s 2>/dev/null || echo "0")
        duration=$((end_epoch - start_epoch))
    fi
    
    # Generate results.yaml
    {
        echo "metadata:"
        echo "  testPass: \"${TEST_TYPE}-$(basename "$TEST_PASS_DIR")\""
        echo "  testType: \"$TEST_TYPE\""
        echo "  startedAt: \"${start_time:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}\""
        echo "  completedAt: \"${end_time:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}\""
        echo "  duration: ${duration}s"
        echo "  platform: \"$(uname -m)\""
        echo "  os: \"$(uname -s)\""
        echo "  workerCount: $WORKERS"
        echo ""
        echo "summary:"
        echo "  total: $total"
        echo "  passed: $passed"
        echo "  failed: $failed"
        echo "  passRate: $(awk "BEGIN {printf \"%.1f\", $passed/$total*100}" 2>/dev/null || echo "0.0")%"
        echo ""
        echo "tests:"
        
        # Add individual test results
        for file in "${result_files[@]}"; do
            if [[ -f "$file" ]]; then
                echo "  - $(yq eval '. | to_entries | map(select(.key != "timestamp")) | from_entries' "$file" | sed 's/^/    /')"
            fi
        done
    } > "$results_yaml"
}

generate_results_markdown() {
    local results_yaml="${TEST_PASS_DIR}/results.yaml"
    local results_md="${TEST_PASS_DIR}/results.md"
    
    if [[ ! -f "$results_yaml" ]]; then
        echo "Results YAML not found: $results_yaml"
        return 1
    fi
    
    # Extract metadata and summary
    local test_pass started_at completed_at duration total passed failed pass_rate
    test_pass=$(yq eval '.metadata.testPass' "$results_yaml")
    started_at=$(yq eval '.metadata.startedAt' "$results_yaml")
    completed_at=$(yq eval '.metadata.completedAt' "$results_yaml")
    duration=$(yq eval '.metadata.duration' "$results_yaml")
    total=$(yq eval '.summary.total' "$results_yaml")
    passed=$(yq eval '.summary.passed' "$results_yaml")
    failed=$(yq eval '.summary.failed' "$results_yaml")
    pass_rate=$(yq eval '.summary.passRate' "$results_yaml")
    
    {
        echo "# JS-libp2p Echo Interoperability Test Results"
        echo ""
        echo "**Test Pass:** $test_pass  "
        echo "**Started:** $started_at  "
        echo "**Completed:** $completed_at  "
        echo "**Duration:** ${duration}s  "
        echo ""
        echo "## Summary"
        echo ""
        echo "| Metric | Value |"
        echo "|--------|-------|"
        echo "| Total Tests | $total |"
        echo "| Passed | $passed |"
        echo "| Failed | $failed |"
        echo "| Pass Rate | $pass_rate |"
        echo ""
        
        if [[ "$failed" -gt 0 ]]; then
            echo "## Failed Tests"
            echo ""
            echo "| Test | Client | Server | Transport | Security | Muxer | Error |"
            echo "|------|--------|--------|-----------|----------|-------|-------|"
            
            yq eval '.tests[] | select(.status == "failed" or .status == "fail")' "$results_yaml" | \
            while IFS= read -r line; do
                if [[ "$line" =~ ^testName: ]]; then
                    test_name=$(echo "$line" | sed 's/testName: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^client: ]]; then
                    client=$(echo "$line" | sed 's/client: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^server: ]]; then
                    server=$(echo "$line" | sed 's/server: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^transport: ]]; then
                    transport=$(echo "$line" | sed 's/transport: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^security: ]]; then
                    security=$(echo "$line" | sed 's/security: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^muxer: ]]; then
                    muxer=$(echo "$line" | sed 's/muxer: "//' | sed 's/"$//')
                elif [[ "$line" =~ ^error: ]]; then
                    error=$(echo "$line" | sed 's/error: "//' | sed 's/"$//' | head -c 50)
                    echo "| $test_name | $client | $server | $transport | $security | $muxer | $error |"
                fi
            done
            echo ""
        fi
        
        echo "## All Test Results"
        echo ""
        echo "| Status | Test | Client | Server | Transport | Security | Muxer | Duration |"
        echo "|--------|------|--------|--------|-----------|----------|-------|----------|"
        
        yq eval '.tests[]' "$results_yaml" | \
        while IFS= read -r line; do
            if [[ "$line" =~ ^testName: ]]; then
                test_name=$(echo "$line" | sed 's/testName: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^status: ]]; then
                status=$(echo "$line" | sed 's/status: "//' | sed 's/"$//')
                status_icon="❓"
                case "$status" in
                    "passed"|"pass") status_icon="✅" ;;
                    "failed"|"fail") status_icon="❌" ;;
                esac
            elif [[ "$line" =~ ^client: ]]; then
                client=$(echo "$line" | sed 's/client: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^server: ]]; then
                server=$(echo "$line" | sed 's/server: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^transport: ]]; then
                transport=$(echo "$line" | sed 's/transport: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^security: ]]; then
                security=$(echo "$line" | sed 's/security: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^muxer: ]]; then
                muxer=$(echo "$line" | sed 's/muxer: "//' | sed 's/"$//')
            elif [[ "$line" =~ ^duration: ]]; then
                duration_ms=$(echo "$line" | sed 's/duration: //')
                echo "| $status_icon | $test_name | $client | $server | $transport | $security | $muxer | ${duration_ms}ms |"
            fi
        done
        
        echo ""
        echo "---"
        echo "*Generated at $(date -u +"%Y-%m-%d %H:%M:%S UTC")*"
        
    } > "$results_md"
}

generate_results_html() {
    local results_md="${TEST_PASS_DIR}/results.md"
    local results_html="${TEST_PASS_DIR}/results.html"
    
    if [[ ! -f "$results_md" ]]; then
        echo "Results markdown not found: $results_md"
        return 1
    fi
    
    # Convert markdown to HTML (basic conversion)
    {
        echo "<!DOCTYPE html>"
        echo "<html lang=\"en\">"
        echo "<head>"
        echo "    <meta charset=\"UTF-8\">"
        echo "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        echo "    <title>JS-libp2p Echo Interoperability Test Results</title>"
        echo "    <style>"
        echo "        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; }"
        echo "        table { border-collapse: collapse; width: 100%; margin: 20px 0; }"
        echo "        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }"
        echo "        th { background-color: #f2f2f2; }"
        echo "        .pass { color: #28a745; }"
        echo "        .fail { color: #dc3545; }"
        echo "        pre { background-color: #f8f9fa; padding: 10px; border-radius: 4px; }"
        echo "    </style>"
        echo "</head>"
        echo "<body>"
        
        # Convert markdown to HTML (basic)
        sed -e 's/^# \(.*\)/<h1>\1<\/h1>/' \
            -e 's/^## \(.*\)/<h2>\1<\/h2>/' \
            -e 's/^### \(.*\)/<h3>\1<\/h3>/' \
            -e 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g' \
            -e 's/^\| \(.*\) \|/<tr><td>\1<\/td><\/tr>/' \
            -e 's/^|-----.*/<\/thead><tbody>/' \
            -e 's/^| \([^|]*\) |/<table><thead><tr><th>\1<\/th><\/tr>/' \
            -e 's/✅/<span class="pass">✅<\/span>/g' \
            -e 's/❌/<span class="fail">❌<\/span>/g' \
            "$results_md"
        
        echo "</tbody></table>"
        echo "</body>"
        echo "</html>"
    } > "$results_html"
}