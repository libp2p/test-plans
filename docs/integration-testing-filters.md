# Integration Testing: Two-Stage Filtering

## Overview

This document describes integration tests for the two-stage filtering system implemented across all test suites (perf, hole-punch, transport).

## Test Environment Setup

```bash
cd /srv/test-plans
export DEBUG=false
export AUTO_YES=true
```

## Integration Tests

### Test 1: Basic SELECT narrows implementations

**Objective**: Verify that `--impl-select` narrows to only matching implementations

**Commands**:
```bash
cd perf
./run.sh --impl-select "rust" --list-tests
```

**Expected**:
- Only rust implementations appear in test matrix
- Test count reflects rust-only combinations
- No go/js/nim implementations in output

---

### Test 2: Basic IGNORE removes from selection

**Objective**: Verify that `--impl-ignore` removes matching implementations

**Commands**:
```bash
cd perf
./run.sh --impl-ignore "experimental" --list-tests
```

**Expected**:
- All implementations except those matching "experimental"
- Test count reduced by experimental implementation combinations
- "experimental" does not appear in selected tests

---

### Test 3: Two-stage filtering (SELECT then IGNORE)

**Objective**: Verify two-stage filtering works correctly

**Commands**:
```bash
cd perf
./run.sh --impl-select "rust|go" --impl-ignore "v0.55" --list-tests
```

**Expected**:
- Stage 1: Only rust and go implementations
- Stage 2: Remove v0.55 versions
- Result: rust-v0.56, rust-v0.54, go-v0.45, go-v0.44 (no v0.55)

---

### Test 4: Transport filtering

**Objective**: Verify transport SELECT and IGNORE work

**Commands**:
```bash
cd perf
./run.sh --transport-select "tcp|quic" --transport-ignore "quic-v1" --list-tests
```

**Expected**:
- Only tcp and quic transports selected
- quic-v1 removed from selection
- Result: tcp and other quic variants (not quic-v1)

---

### Test 5: Component filtering combination

**Objective**: Verify multiple component filters work together

**Commands**:
```bash
cd perf
./run.sh --secure-select "noise|tls" \
         --secure-ignore "tls" \
         --muxer-select "yamux|mplex" \
         --list-tests
```

**Expected**:
- Secure: noise only (selected noise|tls, then ignored tls)
- Muxer: yamux and mplex
- All test combinations reflect these constraints

---

### Test 6: Test name filtering with SELECT

**Objective**: Verify `--test-select` filters by test name

**Commands**:
```bash
cd perf
./run.sh --test-select "rust-v0.56 x rust" --list-tests
```

**Expected**:
- Only tests with "rust-v0.56 x rust" in the name
- Includes rust-v0.56 x rust-v0.56, rust-v0.56 x rust-v0.55, etc.
- Excludes all other dialers

---

### Test 7: Test name filtering with IGNORE

**Objective**: Verify `--test-ignore` filters by test name

**Commands**:
```bash
cd perf
./run.sh --test-ignore " x go-" --list-tests
```

**Expected**:
- All tests EXCEPT those with " x go-" (listener is go)
- Includes rust x rust, go x rust, etc.
- Excludes rust x go, go x go, etc.

---

### Test 8: Combined test name filtering

**Objective**: Verify SELECT and IGNORE work together for test names

**Commands**:
```bash
cd perf
./run.sh --test-select "rust" --test-ignore "experimental" --list-tests
```

**Expected**:
- Select: All tests containing "rust"
- Ignore: Remove tests containing "experimental"
- Result: rust tests excluding experimental versions

---

### Test 9: Empty filters (defaults)

**Objective**: Verify empty filters work correctly

**Commands**:
```bash
cd perf
./run.sh --impl-select "" --impl-ignore "" --list-tests
```

**Expected**:
- SELECT empty = select all
- IGNORE empty = ignore none
- Result: All implementations included

---

### Test 10: Baseline filtering (perf only)

**Objective**: Verify baseline SELECT and IGNORE work

**Commands**:
```bash
cd perf
./run.sh --baseline-select "iperf|https" --baseline-ignore "https" --list-tests
```

**Expected**:
- Baseline selected: iperf only (selected iperf|https, ignored https)
- Baseline tests only use iperf

---

### Test 11: Relay/Router filtering (hole-punch only)

**Objective**: Verify hole-punch specific filters work

**Commands**:
```bash
cd hole-punch
./run.sh --relay-select "go|rust" \
         --relay-ignore "experimental" \
         --router-select "rust" \
         --list-tests
```

**Expected**:
- Relays: go and rust (minus experimental)
- Routers: rust only
- Test matrix reflects these constraints

---

### Test 12: Alias expansion with SELECT

**Objective**: Verify aliases work with SELECT filters

**Commands**:
```bash
cd perf
./run.sh --impl-select "~rust" --list-tests
```

**Expected**:
- Alias ~rust expands to all rust versions
- Only rust implementations in output
- Filter expansion shown in output

---

### Test 13: Cache key computation

**Objective**: Verify cache keys change with different filters

**Commands**:
```bash
cd perf
./run.sh --impl-select "rust" --list-tests 2>&1 | grep "TEST_RUN_KEY"
./run.sh --impl-select "go" --list-tests 2>&1 | grep "TEST_RUN_KEY"
```

**Expected**:
- Two different TEST_RUN_KEY values
- Cache keys computed from all filter parameters
- Different filters = different cache keys

---

### Test 14: Actual test execution

**Objective**: Verify tests execute with filtering applied

**Commands**:
```bash
cd perf
./run.sh --impl-select "rust-v0.56" \
         --transport-select "tcp" \
         --iterations 1 \
         --yes
```

**Expected**:
- Only rust-v0.56 tests execute
- Only tcp transport used
- Tests complete successfully
- Results written to results.yaml

---

### Test 15: inputs.yaml captures all filters

**Objective**: Verify inputs.yaml includes all filter variables

**Commands**:
```bash
cd perf
./run.sh --impl-select "rust" \
         --impl-ignore "experimental" \
         --transport-select "tcp" \
         --list-tests
# Then check generated inputs.yaml
cat /srv/cache/test-run/perf-*/inputs.yaml | grep -E "IMPL_SELECT|IMPL_IGNORE|TRANSPORT_SELECT"
```

**Expected**:
- IMPL_SELECT: "rust" in inputs.yaml
- IMPL_IGNORE: "experimental" in inputs.yaml
- TRANSPORT_SELECT: "tcp" in inputs.yaml
- All filter variables captured

---

## Automated Integration Test Script

Create `test-filtering-integration.sh`:

```bash
#!/bin/bash

set -e

echo "Running integration tests for two-stage filtering..."
cd /srv/test-plans

# Test 1: SELECT narrows
echo "Test 1: SELECT narrows implementations"
output=$(cd perf && ./run.sh --impl-select "rust" --list-tests 2>&1)
if echo "$output" | grep -q "rust-v0.56" && ! echo "$output" | grep -q "go-v0.45"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  exit 1
fi

# Test 2: IGNORE removes
echo "Test 2: IGNORE removes implementations"
output=$(cd perf && ./run.sh --impl-ignore "rust" --list-tests 2>&1)
if ! echo "$output" | grep -q "rust-v0.56" && echo "$output" | grep -q "go-v0.45"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  exit 1
fi

# Test 3: Two-stage filtering
echo "Test 3: Two-stage filtering"
output=$(cd perf && ./run.sh --impl-select "rust|go" --impl-ignore "v0.56" --list-tests 2>&1)
if ! echo "$output" | grep -q "rust-v0.56" && echo "$output" | grep -q "rust-v0.55"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  exit 1
fi

# Test 4: Cache keys differ
echo "Test 4: Cache keys differ with different filters"
key1=$(cd perf && ./run.sh --impl-select "rust" --list-tests 2>&1 | grep "TEST_RUN_KEY" | head -1)
key2=$(cd perf && ./run.sh --impl-select "go" --list-tests 2>&1 | grep "TEST_RUN_KEY" | head -1)
if [ "$key1" != "$key2" ]; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  exit 1
fi

echo ""
echo "All integration tests passed!"
```

## Test Execution

Run all integration tests:

```bash
chmod +x test-filtering-integration.sh
./test-filtering-integration.sh
```

Or run individual tests manually using the commands above.

## Success Criteria

All integration tests should:
1. Complete without errors
2. Produce expected output
3. Generate correct test matrices
4. Execute tests with proper filtering
5. Capture configuration in inputs.yaml
