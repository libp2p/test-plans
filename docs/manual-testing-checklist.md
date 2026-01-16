# Manual Testing Checklist: Two-Stage Filtering

## Overview

This checklist covers comprehensive manual testing of the two-stage filtering system across all test suites.

## Test Environment

- [ ] Clean cache directory: `rm -rf /srv/cache/test-run/*`
- [ ] Verify dependencies: `cd perf && ./run.sh --check-deps`
- [ ] Set AUTO_YES for non-interactive testing: `export AUTO_YES=true`

---

## Perf Test Suite

### Implementation Filtering

- [ ] `--impl-select` narrows to rust only
  ```bash
  cd perf && ./run.sh --impl-select "rust" --list-tests
  ```
  - Verify: Only rust implementations listed
  - Verify: Test count reflects rust-only combinations

- [ ] `--impl-ignore` removes experimental
  ```bash
  cd perf && ./run.sh --impl-ignore "experimental" --list-tests
  ```
  - Verify: No experimental implementations
  - Verify: Other implementations present

- [ ] Two-stage: select rust|go, ignore v0.55
  ```bash
  cd perf && ./run.sh --impl-select "rust|go" --impl-ignore "v0.55" --list-tests
  ```
  - Verify: Only rust and go implementations
  - Verify: No v0.55 versions
  - Verify: Stage 1 and Stage 2 messages shown

### Baseline Filtering

- [ ] `--baseline-select` selects iperf only
  ```bash
  cd perf && ./run.sh --baseline-select "iperf" --list-tests
  ```
  - Verify: Only iperf baseline tests
  - Verify: Baseline section shows iperf only

- [ ] `--baseline-ignore` removes https baseline
  ```bash
  cd perf && ./run.sh --baseline-ignore "https" --list-tests
  ```
  - Verify: https baseline excluded
  - Verify: Other baselines present

- [ ] Two-stage baseline filtering
  ```bash
  cd perf && ./run.sh --baseline-select "iperf|https" --baseline-ignore "https" --list-tests
  ```
  - Verify: Only iperf remains

### Transport Filtering

- [ ] `--transport-select` selects tcp|quic
  ```bash
  cd perf && ./run.sh --transport-select "tcp|quic" --list-tests
  ```
  - Verify: Only tcp and quic transports
  - Verify: Test combinations reflect constraint

- [ ] `--transport-ignore` removes quic-v1
  ```bash
  cd perf && ./run.sh --transport-ignore "quic-v1" --list-tests
  ```
  - Verify: No quic-v1 tests
  - Verify: Other transports present

- [ ] Two-stage transport filtering
  ```bash
  cd perf && ./run.sh --transport-select "tcp|quic" --transport-ignore "quic-v1" --list-tests
  ```
  - Verify: tcp and quic (excluding quic-v1)

### Secure Channel Filtering

- [ ] `--secure-select` selects noise|tls
  ```bash
  cd perf && ./run.sh --secure-select "noise|tls" --list-tests
  ```
  - Verify: Only noise and tls in tests
  - Verify: No other secure channels

- [ ] `--secure-ignore` removes tls
  ```bash
  cd perf && ./run.sh --secure-ignore "tls" --list-tests
  ```
  - Verify: No tls in test combinations
  - Verify: noise and other secure channels present

- [ ] Two-stage secure filtering
  ```bash
  cd perf && ./run.sh --secure-select "noise|tls" --secure-ignore "tls" --list-tests
  ```
  - Verify: Only noise remains

### Muxer Filtering

- [ ] `--muxer-select` selects yamux
  ```bash
  cd perf && ./run.sh --muxer-select "yamux" --list-tests
  ```
  - Verify: Only yamux in tests
  - Verify: mplex excluded

- [ ] `--muxer-ignore` removes mplex
  ```bash
  cd perf && ./run.sh --muxer-ignore "mplex" --list-tests
  ```
  - Verify: No mplex in tests
  - Verify: yamux and others present

- [ ] Two-stage muxer filtering
  ```bash
  cd perf && ./run.sh --muxer-select "yamux|mplex" --muxer-ignore "mplex" --list-tests
  ```
  - Verify: Only yamux remains

### Test Name Filtering

- [ ] `--test-select` filters by test ID
  ```bash
  cd perf && ./run.sh --test-select "rust-v0.56 x rust" --list-tests
  ```
  - Verify: Only tests with "rust-v0.56 x rust" in name
  - Verify: Includes rust-v0.56 x rust-v0.56, rust-v0.56 x rust-v0.55

- [ ] `--test-ignore` excludes by test ID
  ```bash
  cd perf && ./run.sh --test-ignore " x go-" --list-tests
  ```
  - Verify: No tests with " x go-" (go listener)
  - Verify: rust x rust, go x rust present

- [ ] Two-stage test name filtering
  ```bash
  cd perf && ./run.sh --test-select "rust" --test-ignore "experimental" --list-tests
  ```
  - Verify: Only rust tests without experimental

### Combined Filtering

- [ ] All filters together
  ```bash
  cd perf && ./run.sh \
    --impl-select "rust|go" \
    --impl-ignore "v0.54" \
    --transport-select "tcp" \
    --secure-select "noise" \
    --muxer-select "yamux" \
    --list-tests
  ```
  - Verify: rust and go (no v0.54)
  - Verify: tcp only
  - Verify: noise only
  - Verify: yamux only
  - Verify: All constraints respected

### Alias Expansion

- [ ] Alias with SELECT
  ```bash
  cd perf && ./run.sh --impl-select "~rust" --list-tests
  ```
  - Verify: Filter expansion shown
  - Verify: ~rust expands to all rust versions
  - Verify: Only rust implementations selected

- [ ] Negated alias with IGNORE
  ```bash
  cd perf && ./run.sh --impl-ignore "!~rust" --list-tests
  ```
  - Verify: Everything EXCEPT rust excluded
  - Verify: Only rust implementations remain

### Empty Filters

- [ ] Empty SELECT (select all)
  ```bash
  cd perf && ./run.sh --impl-select "" --list-tests
  ```
  - Verify: All implementations selected
  - Verify: Message: "No impl-select specified"

- [ ] Empty IGNORE (ignore none)
  ```bash
  cd perf && ./run.sh --impl-ignore "" --list-tests
  ```
  - Verify: No implementations ignored
  - Verify: Message: "No impl-ignore specified"

### Cache Management

- [ ] Cache key changes with different filters
  ```bash
  cd perf
  KEY1=$(./run.sh --impl-select "rust" --list-tests 2>&1 | grep "TEST_RUN_KEY" | awk '{print $2}')
  KEY2=$(./run.sh --impl-select "go" --list-tests 2>&1 | grep "TEST_RUN_KEY" | awk '{print $2}')
  [ "$KEY1" != "$KEY2" ] && echo "✓ Different keys" || echo "✗ Same keys"
  ```
  - Verify: Two different cache keys
  - Verify: Keys are 8-char hex strings

- [ ] Cache hit on repeated call
  ```bash
  cd perf && ./run.sh --impl-select "rust" --list-tests
  cd perf && ./run.sh --impl-select "rust" --list-tests
  ```
  - Verify: Second call shows "Using cached test-matrix.yaml"

- [ ] Force rebuild invalidates cache
  ```bash
  cd perf && ./run.sh --impl-select "rust" --force-matrix-rebuild --list-tests
  ```
  - Verify: "Regenerating test-matrix.yaml" shown
  - Verify: Cache rebuilt even if exists

### Test Execution

- [ ] Execute with filtering
  ```bash
  cd perf && ./run.sh \
    --impl-select "rust-v0.56" \
    --transport-select "tcp" \
    --iterations 1 \
    --yes
  ```
  - Verify: Only rust-v0.56 tests execute
  - Verify: Only tcp transport used
  - Verify: Tests complete successfully
  - Verify: Results written

### inputs.yaml Capture

- [ ] All filters captured in inputs.yaml
  ```bash
  cd perf && ./run.sh \
    --impl-select "rust" \
    --impl-ignore "experimental" \
    --baseline-select "iperf" \
    --transport-select "tcp" \
    --secure-select "noise" \
    --muxer-select "yamux" \
    --test-select "rust-v0.56" \
    --list-tests
  cat /srv/cache/test-run/perf-*/inputs.yaml
  ```
  - Verify: IMPL_SELECT present
  - Verify: IMPL_IGNORE present
  - Verify: BASELINE_SELECT present
  - Verify: TRANSPORT_SELECT present
  - Verify: SECURE_SELECT present
  - Verify: MUXER_SELECT present
  - Verify: TEST_SELECT present
  - Verify: TEST_IGNORE present

---

## Hole-Punch Test Suite

### Additional Filtering (Relay/Router)

- [ ] `--relay-select` selects go|rust relays
  ```bash
  cd hole-punch && ./run.sh --relay-select "go|rust" --list-tests
  ```
  - Verify: Only go and rust relays

- [ ] `--relay-ignore` removes experimental
  ```bash
  cd hole-punch && ./run.sh --relay-ignore "experimental" --list-tests
  ```
  - Verify: No experimental relays

- [ ] Two-stage relay filtering
  ```bash
  cd hole-punch && ./run.sh --relay-select "go|rust" --relay-ignore "v0.55" --list-tests
  ```
  - Verify: go and rust (no v0.55)

- [ ] `--router-select` selects rust only
  ```bash
  cd hole-punch && ./run.sh --router-select "rust" --list-tests
  ```
  - Verify: Only rust routers

- [ ] `--router-ignore` removes experimental
  ```bash
  cd hole-punch && ./run.sh --router-ignore "experimental" --list-tests
  ```
  - Verify: No experimental routers

- [ ] Combined relay/router filtering
  ```bash
  cd hole-punch && ./run.sh \
    --relay-select "go|rust" \
    --relay-ignore "experimental" \
    --router-select "rust" \
    --list-tests
  ```
  - Verify: Relays: go and rust (no experimental)
  - Verify: Routers: rust only

### All Hole-Punch Filters

- [ ] All dimensions together
  ```bash
  cd hole-punch && ./run.sh \
    --impl-select "rust|go" \
    --relay-select "go" \
    --router-select "rust" \
    --transport-select "tcp" \
    --list-tests
  ```
  - Verify: All constraints respected in test matrix

---

## Transport Test Suite

### Basic Filtering (No Baseline/Relay/Router)

- [ ] Implementation filtering works
  ```bash
  cd transport && ./run.sh --impl-select "rust" --list-tests
  ```
  - Verify: Only rust implementations

- [ ] Transport filtering works
  ```bash
  cd transport && ./run.sh --transport-select "tcp|quic" --list-tests
  ```
  - Verify: Only tcp and quic

- [ ] Secure channel filtering works
  ```bash
  cd transport && ./run.sh --secure-select "noise" --list-tests
  ```
  - Verify: Only noise secure channel

- [ ] Muxer filtering works
  ```bash
  cd transport && ./run.sh --muxer-select "yamux" --list-tests
  ```
  - Verify: Only yamux muxer

- [ ] Test name filtering works
  ```bash
  cd transport && ./run.sh --test-select "rust-v0.56 x rust" --list-tests
  ```
  - Verify: Only matching test names

### Combined Transport Filters

- [ ] All filters together
  ```bash
  cd transport && ./run.sh \
    --impl-select "rust|go" \
    --transport-select "tcp" \
    --secure-select "noise" \
    --muxer-select "yamux" \
    --list-tests
  ```
  - Verify: All constraints respected

---

## Help Text and Documentation

### Help Text

- [ ] Perf help shows all flags
  ```bash
  cd perf && ./run.sh --help
  ```
  - Verify: --impl-select documented
  - Verify: --impl-ignore documented (not --test-ignore for impl)
  - Verify: --baseline-select documented
  - Verify: --baseline-ignore documented
  - Verify: All component SELECT/IGNORE flags documented
  - Verify: --test-select documented (for test names)
  - Verify: --test-ignore documented (for test names)

- [ ] Hole-punch help complete
  ```bash
  cd hole-punch && ./run.sh --help
  ```
  - Verify: All perf flags plus relay/router

- [ ] Transport help complete
  ```bash
  cd transport && ./run.sh --help
  ```
  - Verify: All flags except baseline/relay/router

### CLAUDE.md

- [ ] Read /srv/test-plans/CLAUDE.md
  - Verify: Two-stage filtering explained
  - Verify: All filter variables documented
  - Verify: Examples use new syntax
  - Verify: No references to old --test-ignore for implementations

### inputs-schema.md

- [ ] Read /srv/test-plans/docs/inputs-schema.md
  - Verify: All SELECT/IGNORE variables documented
  - Verify: Filter processing order explained
  - Verify: Examples accurate

---

## Breaking Changes

### Verify Old --test-ignore No Longer Works for Implementations

- [ ] Old syntax should fail or behave differently
  ```bash
  cd perf && ./run.sh --test-ignore "rust" --list-tests
  ```
  - Verify: This now filters TEST NAMES, not implementations
  - Verify: Does NOT exclude rust implementations
  - Verify: Would exclude tests with "rust" in the test name

### New --impl-ignore Behavior

- [ ] New syntax for implementation filtering
  ```bash
  cd perf && ./run.sh --impl-ignore "rust" --list-tests
  ```
  - Verify: This excludes rust implementations
  - Verify: Correct behavior for implementation filtering

---

## Summary Checklist

Mark when complete:

- [ ] All perf test suite checks complete
- [ ] All hole-punch test suite checks complete
- [ ] All transport test suite checks complete
- [ ] Help text and documentation verified
- [ ] Breaking changes verified
- [ ] No regressions found
- [ ] All filters work as expected
- [ ] Cache system works correctly
- [ ] Test execution works with filtering
- [ ] inputs.yaml captures configuration

---

## Known Issues / Notes

Record any issues found during testing:

1. _______________________________________________
2. _______________________________________________
3. _______________________________________________

---

## Sign-off

Tester: ________________  Date: ________

All tests completed successfully: [ ] Yes [ ] No
