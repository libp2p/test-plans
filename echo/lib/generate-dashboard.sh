#!/bin/bash
# Generate HTML dashboard for Echo protocol test results
# Usage: generate-dashboard.sh <results-dir>

set -euo pipefail

##### 1. SETUP

RESULTS_DIR="${1:-results}"
DASHBOARD_FILE="${RESULTS_DIR}/echo-dashboard.html"

if [[ ! -d "${RESULTS_DIR}" ]]; then
    echo "ERROR: Results directory not found: ${RESULTS_DIR}" >&2
    exit 1
fi

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

##### 2. COLLECT RESULTS

print_message "Generating Echo protocol dashboard..."

# Find all result files
RESULT_FILES=($(find "${RESULTS_DIR}" -name "*.json" -type f))

if [[ ${#RESULT_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No result files found in ${RESULTS_DIR}" >&2
    exit 1
fi

# Parse results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
declare -A RESULTS_BY_COMBO

for result_file in "${RESULT_FILES[@]}"; do
    if [[ -f "${result_file}" ]]; then
        TEST_NAME=$(jq -r '.test' "${result_file}" 2>/dev/null || echo "unknown")
        RESULT=$(jq -r '.result' "${result_file}" 2>/dev/null || echo "FAIL")
        SERVER=$(jq -r '.server' "${result_file}" 2>/dev/null || echo "unknown")
        CLIENT=$(jq -r '.client' "${result_file}" 2>/dev/null || echo "unknown")
        TRANSPORT=$(jq -r '.transport' "${result_file}" 2>/dev/null || echo "unknown")
        SECURE=$(jq -r '.secureChannel' "${result_file}" 2>/dev/null || echo "unknown")
        MUXER=$(jq -r '.muxer' "${result_file}" 2>/dev/null || echo "unknown")
        
        COMBO_KEY="${SERVER}|${CLIENT}|${TRANSPORT}|${SECURE}|${MUXER}"
        RESULTS_BY_COMBO["${COMBO_KEY}"]="${RESULT}"
        
        ((TOTAL_TESTS++))
        if [[ "${RESULT}" == "PASS" ]]; then
            ((PASSED_TESTS++))
        else
            ((FAILED_TESTS++))
        fi
    fi
done

##### 3. GENERATE HTML DASHBOARD

cat > "${DASHBOARD_FILE}" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Echo Protocol Interoperability Test Results</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 30px;
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }
        .summary {
            display: flex;
            justify-content: space-around;
            margin-bottom: 40px;
            text-align: center;
        }
        .summary-item {
            padding: 20px;
            border-radius: 8px;
            min-width: 120px;
        }
        .summary-total { background-color: #e3f2fd; }
        .summary-passed { background-color: #e8f5e8; }
        .summary-failed { background-color: #ffebee; }
        .summary-number {
            font-size: 2em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .results-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        .results-table th,
        .results-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        .results-table th {
            background-color: #f8f9fa;
            font-weight: 600;
        }
        .result-pass {
            color: #28a745;
            font-weight: bold;
        }
        .result-fail {
            color: #dc3545;
            font-weight: bold;
        }
        .protocol-badge {
            background-color: #007bff;
            color: white;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.8em;
        }
        .footer {
            margin-top: 40px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Echo Protocol Interoperability Test Results</h1>
        
        <div class="summary">
            <div class="summary-item summary-total">
                <div class="summary-number">TOTAL_TESTS_PLACEHOLDER</div>
                <div>Total Tests</div>
            </div>
            <div class="summary-item summary-passed">
                <div class="summary-number">PASSED_TESTS_PLACEHOLDER</div>
                <div>Passed</div>
            </div>
            <div class="summary-item summary-failed">
                <div class="summary-number">FAILED_TESTS_PLACEHOLDER</div>
                <div>Failed</div>
            </div>
        </div>

        <table class="results-table">
            <thead>
                <tr>
                    <th>Server</th>
                    <th>Client</th>
                    <th>Transport</th>
                    <th>Security</th>
                    <th>Muxer</th>
                    <th>Protocol</th>
                    <th>Result</th>
                </tr>
            </thead>
            <tbody>
                RESULTS_TABLE_PLACEHOLDER
            </tbody>
        </table>

        <div class="footer">
            <p>Generated on TIMESTAMP_PLACEHOLDER</p>
            <p>Echo Protocol (/echo/1.0.0) validates full bidirectional stream capabilities</p>
        </div>
    </div>
</body>
</html>
EOF

# Replace placeholders
sed -i.bak "s/TOTAL_TESTS_PLACEHOLDER/${TOTAL_TESTS}/g" "${DASHBOARD_FILE}"
sed -i.bak "s/PASSED_TESTS_PLACEHOLDER/${PASSED_TESTS}/g" "${DASHBOARD_FILE}"
sed -i.bak "s/FAILED_TESTS_PLACEHOLDER/${FAILED_TESTS}/g" "${DASHBOARD_FILE}"
sed -i.bak "s/TIMESTAMP_PLACEHOLDER/$(date -u +"%Y-%m-%d %H:%M:%S UTC")/g" "${DASHBOARD_FILE}"

# Generate results table
TABLE_ROWS=""
for combo_key in "${!RESULTS_BY_COMBO[@]}"; do
    IFS='|' read -r server client transport secure muxer <<< "${combo_key}"
    result="${RESULTS_BY_COMBO[${combo_key}]}"
    
    if [[ "${result}" == "PASS" ]]; then
        result_class="result-pass"
        result_symbol="✅ PASS"
    else
        result_class="result-fail"
        result_symbol="❌ FAIL"
    fi
    
    TABLE_ROWS+="<tr>"
    TABLE_ROWS+="<td>${server}</td>"
    TABLE_ROWS+="<td>${client}</td>"
    TABLE_ROWS+="<td>${transport}</td>"
    TABLE_ROWS+="<td>${secure}</td>"
    TABLE_ROWS+="<td>${muxer}</td>"
    TABLE_ROWS+="<td><span class=\"protocol-badge\">/echo/1.0.0</span></td>"
    TABLE_ROWS+="<td class=\"${result_class}\">${result_symbol}</td>"
    TABLE_ROWS+="</tr>"
done

sed -i.bak "s|RESULTS_TABLE_PLACEHOLDER|${TABLE_ROWS}|g" "${DASHBOARD_FILE}"

# Clean up backup file
rm -f "${DASHBOARD_FILE}.bak"

##### 4. RESULTS

print_message "Dashboard generated: ${DASHBOARD_FILE}"
print_message "Summary: ${PASSED_TESTS}/${TOTAL_TESTS} tests passed"

if [[ "${FAILED_TESTS}" -gt 0 ]]; then
    print_message "⚠️  ${FAILED_TESTS} tests failed - check dashboard for details"
fi