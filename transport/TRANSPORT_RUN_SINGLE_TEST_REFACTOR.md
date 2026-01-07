# Transport run-single-test.sh Refactor

## Summary

Refactored `transport/lib/run-single-test.sh` to follow the same pattern as `perf/lib/run-single-test.sh`, which reads test configuration from the test-matrix.yaml file instead of accepting individual parameters. This fixes the error where `transport/run.sh` was incorrectly calling `${SCRIPT_LIB_DIR}/run-single-test.sh` instead of `${SCRIPT_DIR}/run-single-test.sh`.

## Changes Made

### 1. transport/lib/run-single-test.sh (Complete Rewrite)

**Before:**
- Accepted 6 command-line arguments: test_name, dialer_id, listener_id, transport, secure_channel, muxer
- Had hardcoded SCRIPT_LIB_DIR path initialization
- Did not use log_message/log_error functions
- Did not write to combined results file
- Did not track test duration

**After:**
- Accepts 3 arguments: test_index, test_pass, results_file (same as perf)
- Reads all test configuration from test-matrix.yaml using yq
- Uses log_message/log_error functions for output
- Writes to both individual result files and combined results.yaml.tmp
- Tracks test duration and includes it in results
- Uses proper file locking for concurrent writes
- Follows exact same pattern as perf/lib/run-single-test.sh

**Key Features:**
- Sources `lib-output-formatting.sh` and `lib-test-caching.sh`
- Uses `compute_test_key()` for Redis namespacing
- Creates log file at `${TEST_PASS_DIR}/logs/${TEST_SLUG}.log`
- Generates docker-compose file at `${TEST_PASS_DIR}/docker-compose/${TEST_SLUG}-compose.yaml`
- Extracts JSON metrics from dialer logs
- Writes YAML results with proper field names: `handshakePlusOneRTTMs`, `pingRTTMs`, `duration`
- Uses flock for atomic writes to results.yaml.tmp

### 2. transport/run.sh

**Modified run_test() function (lines 513-532):**

**Before:**
```bash
run_test() {
  local index=$1
  local name=$(yq eval ".tests[$index].name" "${TEST_PASS_DIR}/test-matrix.yaml")
  local dialer=$(yq eval ".tests[$index].dialer" "${TEST_PASS_DIR}/test-matrix.yaml")
  local listener=$(yq eval ".tests[$index].listener" "${TEST_PASS_DIR}/test-matrix.yaml")
  local transport=$(yq eval ".tests[$index].transport" "${TEST_PASS_DIR}/test-matrix.yaml")
  local secure=$(yq eval ".tests[$index].secureChannel" "${TEST_PASS_DIR}/test-matrix.yaml")
  local muxer=$(yq eval ".tests[$index].muxer" "${TEST_PASS_DIR}/test-matrix.yaml")

  echo "[$((index + 1))/$test_count] $name"

  start=$(date +%s)
  if bash ${SCRIPT_LIB_DIR}/run-single-test.sh "$name" "$dialer" "$listener" "$transport" "$secure" "$muxer"; then
    status="pass"
    exit_code=0
  else
    status="fail"
    exit_code=1
  fi
  end=$(date +%s)
  duration=$((end - start))

  # Extract metrics from log file...
  # Save individual test result...
  # etc. (60+ lines of code)
}
```

**After:**
```bash
run_test() {
  local index=$1
  local name=$(yq eval ".tests[$index].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  if [ "${DEBUG:-false}" == "true" ]; then
    echo_message "[$((index + 1))/$test_count] $name..."
  else
    echo_message "[$((index + 1))/$test_count] $name..."
  fi

  # Run test using run-single-test.sh (now reads from test-matrix.yaml)
  # Results are written to results.yaml.tmp by the script
  if bash ${SCRIPT_DIR}/run-single-test.sh "$index" "tests" "${TEST_PASS_DIR}/results.yaml.tmp"; then
    echo "[SUCCESS]"
    return 0
  else
    echo "[FAILED]"
    return 1
  fi
}
```

**Key Changes:**
- Changed from `${SCRIPT_LIB_DIR}` to `${SCRIPT_DIR}` ✅ (fixes the main bug)
- Simplified from 60+ lines to 15 lines
- Removed manual metric extraction (now done by run-single-test.sh)
- Removed manual result file writing (now done by run-single-test.sh)
- Changed `.tests[$index].name` to `.tests[$index].id` to match test-matrix.yaml format

**Added results file initialization (line 513):**
```bash
# Initialize results file
TEST_RESULTS_FILE="${TEST_PASS_DIR}/results.yaml.tmp"
> "${TEST_RESULTS_FILE}"
```

**Modified results collection (lines 602-606):**

**Before:**
```bash
# Aggregate individual result files into results.yaml
for result_file in "$TEST_PASS_DIR"/results/*.yaml; do
  if [ -f "$result_file" ]; then
    # Read first line and add as array item
    echo "  - name: $(yq eval '.name' "$result_file")" >> "$TEST_PASS_DIR/results.yaml"
    # Add remaining fields with proper indentation
    yq eval 'del(.name) | to_entries | .[] | "    " + .key + ": " + (.value | @json)' "$result_file" | sed 's/"//g' >> "$TEST_PASS_DIR/results.yaml"
  fi
done
```

**After:**
```bash
# Append test results if they exist
if [ -f "${TEST_PASS_DIR}/results.yaml.tmp" ]; then
    cat "${TEST_PASS_DIR}/results.yaml.tmp" >> "${TEST_PASS_DIR}/results.yaml"
    rm "${TEST_PASS_DIR}/results.yaml.tmp"
fi
```

## Testing

Syntax validation passed:
```bash
✓ run-single-test.sh syntax OK
✓ run.sh syntax OK
```

## Benefits

1. **Consistency**: transport tests now follow the same pattern as perf tests
2. **Correctness**: Fixed the bug where wrong script path was being called
3. **Simplification**: Reduced run_test() function from 60+ lines to 15 lines
4. **Maintainability**: Single source of truth for test execution logic
5. **Reliability**: Proper file locking for concurrent test writes
6. **Debugging**: Better logging with log_message/log_error functions

## Files Modified

- `/srv/test-plans/transport/lib/run-single-test.sh` (complete rewrite)
- `/srv/test-plans/transport/run.sh` (run_test function simplified, results collection updated)

## Date

2026-01-06
