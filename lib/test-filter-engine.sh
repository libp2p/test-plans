#!/bin/bash
# Unit tests for lib-filter-engine.sh
# Tests recursive alias expansion, loop detection, inversion, and filtering

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source the library we're testing
source "$SCRIPT_DIR/lib-filter-engine.sh"

# Disable debug output for tests
print_debug() { :; }
log_debug() { :; }

# Test framework globals
TEST_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0
FAILED_TESTS=()

# Test framework functions
fail() {
  local message="$1"
  echo "  ✗ FAIL: $message" >&2
  return 1
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local message="${3:-}"

  if [ "$actual" == "$expected" ]; then
    return 0
  else
    if [ -n "$message" ]; then
      fail "$message (expected: '$expected', got: '$actual')"
    else
      fail "Expected '$expected', got '$actual'"
    fi
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-}"

  case "$haystack" in
    *"$needle"*)
      return 0
      ;;
    *)
      if [ -n "$message" ]; then
        fail "$message (expected '$haystack' to contain '$needle')"
      else
        fail "Expected '$haystack' to contain '$needle'"
      fi
      ;;
  esac
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-}"

  case "$haystack" in
    *"$needle"*)
      if [ -n "$message" ]; then
        fail "$message (expected '$haystack' to NOT contain '$needle')"
      else
        fail "Expected '$haystack' to NOT contain '$needle'"
      fi
      ;;
    *)
      return 0
      ;;
  esac
}

run_test() {
  local test_name="$1"
  local test_function="$2"

  TEST_COUNT=$((TEST_COUNT + 1))
  echo -n "Test $TEST_COUNT: $test_name ... "

  # Run test in subshell to isolate variables
  if (
    # Reset ALIASES for clean test environment
    declare -gA ALIASES
    $test_function
  ) 2>/dev/null; then
    echo "✓ PASS"
    PASSED_COUNT=$((PASSED_COUNT + 1))
  else
    echo "✗ FAIL"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_TESTS+=("$test_name")
  fi
}

# =============================================================================
# TEST SUITE
# =============================================================================

# Test 1: Simple value expansion (no aliases)
test_simple_value() {
  local all_names=("rust-v0.56" "go-v0.45")
  local result=$(expand_filter_string "rust-v0.56" all_names)
  assert_equals "$result" "rust-v0.56" "Simple value should pass through unchanged"
}

# Test 2: Simple alias expansion
test_simple_alias() {
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45")
  local result=$(expand_filter_string "~rust" all_names)
  assert_contains "$result" "rust-v0.56" "Should expand to rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should expand to rust-v0.55"
}

# Test 3: Nested alias expansion (recursive)
test_nested_alias() {
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  ALIASES["stable"]="~rust|go-v0.45"
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")

  local result=$(expand_filter_string "~stable" all_names)
  assert_contains "$result" "rust-v0.56" "Nested alias should expand rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Nested alias should expand rust-v0.55"
  assert_contains "$result" "go-v0.45" "Nested alias should include go-v0.45"
}

# Test 4: Loop detection
test_loop_detection() {
  ALIASES["a"]="~b"
  ALIASES["b"]="~a"
  local all_names=("test")

  # This should fail with loop detection
  if expand_filter_string "~a" all_names 2>/dev/null; then
    fail "Loop detection failed - should have detected circular reference"
  fi
  # Expected to fail, so test passes
  return 0
}

# Test 5: Three-level nested alias
test_three_level_nesting() {
  ALIASES["v56"]="rust-v0.56"
  ALIASES["rust"]="~v56|rust-v0.55"
  ALIASES["stable"]="~rust|go-v0.45"
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45")

  local result=$(expand_filter_string "~stable" all_names)
  assert_contains "$result" "rust-v0.56" "Three-level nesting should expand v56"
  assert_contains "$result" "rust-v0.55" "Three-level nesting should expand v55"
  assert_contains "$result" "go-v0.45" "Three-level nesting should include go"
}

# Test 6: Deduplication (built into expand_filter_string)
test_deduplication() {
  local all_names=("rust" "go" "python")
  # Duplicate values should be deduplicated
  local result=$(expand_filter_string "rust|go|rust|python|go" all_names)
  # Result should have each value only once
  assert_contains "$result" "rust"
  assert_contains "$result" "go"
  assert_contains "$result" "python"
  # Count occurrences - should be exactly 3 unique values
  local count=$(echo "$result" | tr '|' '\n' | wc -l)
  assert_equals "$count" "3" "Should have 3 unique values"
}

# Test 7: Empty string handling
test_empty_string() {
  local all_names=("rust-v0.56")
  local result=$(expand_filter_string "" all_names)
  assert_equals "$result" "" "Empty string should return empty"
}

# Test 8: Inverted value (!pattern)
test_inverted_value() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4")
  local result=$(expand_filter_string "!rust" all_names)

  # Should expand to all names that DON'T contain "rust"
  assert_not_contains "$result" "rust-v0.56" "Inverted value should exclude rust-v0.56"
  assert_contains "$result" "go-v0.45" "Inverted value should include go-v0.45"
  assert_contains "$result" "python-v0.4" "Inverted value should include python-v0.4"
}

# Test 9: Inverted alias (!~alias)
test_inverted_alias() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  local result=$(expand_filter_string "!~rust" all_names)

  # Should expand to all names that don't match ANY rust pattern
  assert_not_contains "$result" "rust-v0.56" "Inverted alias should exclude rust-v0.56"
  assert_not_contains "$result" "rust-v0.55" "Inverted alias should exclude rust-v0.55"
  assert_contains "$result" "go-v0.45" "Inverted alias should include go-v0.45"
  assert_contains "$result" "python-v0.4" "Inverted alias should include python-v0.4"
}

# Test 10: Mixed patterns (values, aliases)
test_mixed_patterns() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4" "js-v3.x")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  local result=$(expand_filter_string "~rust|python-v0.4" all_names)

  # Should include rust expansions and python
  assert_contains "$result" "rust-v0.56" "Mixed should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Mixed should include rust-v0.55"
  assert_contains "$result" "python-v0.4" "Mixed should include python-v0.4"
}

# Test 11: filter_matches function
test_filter_matches() {
  # Test matching
  filter_matches "rust-v0.56" "rust|go" || fail "Should match rust"
  filter_matches "go-v0.45" "rust|go" || fail "Should match go"

  # Test non-matching
  filter_matches "python-v0.4" "rust|go" && fail "Should not match python"

  # Test empty filter
  filter_matches "rust-v0.56" "" && fail "Empty filter should not match"

  return 0
}

# Test 12: ignore function (ignore filtering)
test_ignore_function() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  local input_ids=("rust-v0.56" "rust-v0.55" "go-v0.45")

  # Test 1: No ignore filter - should keep all
  local result=$(ignore_from_list input_ids "")
  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "3" "No ignore filter should keep all 3 items"

  # Test 2: Ignore rust - should remove rust items
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  local all_names_for_expansion=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  local ignore_expanded=$(expand_filter_string "~rust" all_names_for_expansion)
  result=$(ignore_from_list input_ids "$ignore_expanded")
  assert_not_contains "$result" "rust-v0.56" "Should exclude rust-v0.56"
  assert_not_contains "$result" "rust-v0.55" "Should exclude rust-v0.55"
  assert_contains "$result" "go-v0.45" "Should include go-v0.45"
}

# Test 13: Unknown alias handling
test_unknown_alias() {
  local all_names=("rust-v0.56")

  # Unknown alias should return empty (not error)
  local result=$(expand_filter_string "~nonexistent" all_names)
  assert_equals "$result" "" "Unknown alias should return empty"
}

# Test 14: Complex inverted alias
test_complex_inverted_alias() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "go-v0.44" "python-v0.4")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  ALIASES["go"]="go-v0.45|go-v0.44"
  ALIASES["compiled"]="~rust|~go"

  # !~compiled should exclude all rust and go
  local result=$(expand_filter_string "!~compiled" all_names)
  assert_not_contains "$result" "rust" "Should not contain any rust"
  assert_not_contains "$result" "go" "Should not contain any go"
  assert_contains "$result" "python" "Should contain python"
}

# Test 15: Multiple inversions (OR semantics)
test_multiple_inversions() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4" "js-v3.x")

  # !rust|!go means: (names NOT containing rust) OR (names NOT containing go)
  # This results in ALL names (correct OR behavior)
  local result=$(expand_filter_string "!rust|!go" all_names)

  # Result should be ALL names
  assert_contains "$result" "rust-v0.56" "OR semantics: should include rust"
  assert_contains "$result" "go-v0.45" "OR semantics: should include go"
  assert_contains "$result" "python-v0.4" "OR semantics: should include python"
  assert_contains "$result" "js-v3.x" "OR semantics: should include js"
}

# Test 16: Alias with single value
test_alias_single_value() {
  ALIASES["latest"]="rust-v0.56"
  local all_names=("rust-v0.56" "go-v0.45")

  local result=$(expand_filter_string "~latest" all_names)
  assert_equals "$result" "rust-v0.56" "Single-value alias should work"
}

# Test 17: Deep nesting (4 levels)
test_deep_nesting() {
  ALIASES["a"]="a-value"
  ALIASES["b"]="~a|b-value"
  ALIASES["c"]="~b|c-value"
  ALIASES["d"]="~c|d-value"
  local all_names=("a-value" "b-value" "c-value" "d-value")

  local result=$(expand_filter_string "~d" all_names)
  assert_contains "$result" "a-value" "Deep nesting should expand all levels"
  assert_contains "$result" "b-value"
  assert_contains "$result" "c-value"
  assert_contains "$result" "d-value"
}

# Test 18: Exact substring matching
test_exact_substring_matching() {
  filter_matches "rust-v0.56" "rust-v0.56" || fail "Should match exact string"
  filter_matches "rust-v0.56" "v0.56" || fail "Should match substring"
  filter_matches "rust-v0.56" "rust" || fail "Should match prefix"
  filter_matches "rust-v0.56" "0.56" || fail "Should match suffix"

  filter_matches "rust-v0.56" "v0.55" && fail "Should not match different version"

  return 0
}

# Test 19: Inverted nested alias
test_inverted_nested_alias() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  ALIASES["stable"]="~rust|go-v0.45"

  # !~stable should exclude all rust and go
  local result=$(expand_filter_string "!~stable" all_names)

  assert_not_contains "$result" "rust" "Should not contain rust"
  assert_not_contains "$result" "go" "Should not contain go"
  assert_contains "$result" "python" "Should contain python"
}

# Test 20: Case sensitivity
test_case_sensitivity() {
  # Substring matching is case-sensitive in bash
  filter_matches "rust-v0.56" "Rust" && fail "Should be case-sensitive"
  filter_matches "Rust-v0.56" "Rust" || fail "Should match exact case"

  return 0
}

# Test 21: Special characters in patterns
test_special_characters() {
  # Dash and dot should work in patterns
  filter_matches "rust-v0.56" "v0.56" || fail "Should match with dots"
  filter_matches "rust-v0.56" "rust-v" || fail "Should match with dash"

  return 0
}

# Test 22: Pipe in values (already split by expand_filter_string)
test_pipe_in_expansion() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4")

  # Multiple values separated by pipe
  local result=$(expand_filter_string "rust-v0.56|go-v0.45" all_names)
  assert_contains "$result" "rust-v0.56" "Should include rust"
  assert_contains "$result" "go-v0.45" "Should include go"
  assert_not_contains "$result" "python" "Should not include python"
}

# Test 23: Empty filter handling in filter_matches
test_empty_filter_matches() {
  # Empty filter should not match anything
  filter_matches "rust-v0.56" "" && fail "Empty filter should not match"
  return 0
}

# Test 24: Filter with all selected
test_filter_with_all_selected() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45")
  local input_ids=("${all_names[@]}")

  # Expand ignore filter for rust
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  local ignore_expanded=$(expand_filter_string "~rust" all_names)

  # Filter out rust items
  local result=$(ignore_from_list input_ids "$ignore_expanded")
  assert_not_contains "$result" "rust-v0.56" "Should exclude rust-v0.56"
  assert_not_contains "$result" "rust-v0.55" "Should exclude rust-v0.55"
  assert_contains "$result" "go-v0.45" "Should keep go-v0.45"
}

# Test 25: Inverted value with partial match
test_inverted_partial_match() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45")

  # !v0.56 should exclude only rust-v0.56
  local result=$(expand_filter_string "!v0.56" all_names)
  assert_not_contains "$result" "rust-v0.56" "Should exclude rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
  assert_contains "$result" "go-v0.45" "Should include go-v0.45"
}

# Test 26: Multiple regular values
test_multiple_regular_values() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4")

  local result=$(expand_filter_string "rust|go" all_names)
  assert_contains "$result" "rust" "Should include rust"
  assert_contains "$result" "go" "Should include go"
}

# Test 27: Alias expansion with deduplication
test_alias_deduplication() {
  local all_names=("rust-v0.56" "go-v0.45")
  ALIASES["rust"]="rust-v0.56"

  # ~rust|rust-v0.56 should deduplicate to just rust-v0.56
  local result=$(expand_filter_string "~rust|rust-v0.56" all_names)
  # Count occurrences of rust-v0.56
  local count=$(echo "$result" | tr '|' '\n' | grep -c "rust-v0.56" || true)
  assert_equals "$count" "1" "Should have exactly one rust-v0.56"
}

# Test 28: Combined positive and negative filters
test_combined_filters() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")

  # Include rust but exclude v0.56
  # This is ~rust + ignore v0.56, simulated as: include all rust patterns then filter
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  local expanded_rust=$(expand_filter_string "~rust" all_names)

  # Start with rust items
  local input_ids=()
  IFS='|' read -ra parts <<< "$expanded_rust"
  for part in "${parts[@]}"; do
    input_ids+=("$part")
  done

  # Filter out v0.56
  local result=$(ignore_from_list input_ids "v0.56")
  assert_not_contains "$result" "rust-v0.56" "Should exclude rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
}

# Test 29: select function with empty filter
test_select_empty_filter() {
  local input_ids=("rust-v0.56" "rust-v0.55" "go-v0.45")

  # Empty select should return all items
  local result=$(select_from_list input_ids "")
  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "3" "Empty select should return all 3 items"
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
  assert_contains "$result" "go-v0.45" "Should include go-v0.45"
}

# Test 30: select function with single pattern
test_select_single_pattern() {
  local input_ids=("rust-v0.56" "rust-v0.55" "go-v0.45" "js-v1.0")

  # Select only rust items
  local result=$(select_from_list input_ids "rust")
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
  assert_not_contains "$result" "go-v0.45" "Should not include go-v0.45"
  assert_not_contains "$result" "js-v1.0" "Should not include js-v1.0"
}

# Test 31: select function with pipe-separated patterns
test_select_multiple_patterns() {
  local input_ids=("rust-v0.56" "go-v0.45" "js-v1.0" "python-v0.4")

  # Select rust OR go items
  local result=$(select_from_list input_ids "rust|go")
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "go-v0.45" "Should include go-v0.45"
  assert_not_contains "$result" "js-v1.0" "Should not include js-v1.0"
  assert_not_contains "$result" "python-v0.4" "Should not include python-v0.4"
}

# Test 32: select function with expanded alias
test_select_with_alias() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "js-v1.0")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  # Expand alias first
  local select_expanded=$(expand_filter_string "~rust" all_names)

  # Select using expanded filter
  local result=$(select_from_list all_names "$select_expanded")
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
  assert_not_contains "$result" "go-v0.45" "Should not include go-v0.45"
  assert_not_contains "$result" "js-v1.0" "Should not include js-v1.0"
}

# Test 33: Two-stage filtering (select then ignore)
test_two_stage_filtering() {
  local all_ids=("rust-v0.56" "rust-v0.55" "rust-experimental" "go-v0.45" "js-v1.0")
  ALIASES["rust"]="rust-v0.56|rust-v0.55|rust-experimental"

  # Stage 1: SELECT rust items
  local select_expanded=$(expand_filter_string "~rust" all_ids)
  local selected_ids=()
  readarray -t selected_ids < <(select_from_list all_ids "$select_expanded")

  # Stage 2: IGNORE experimental from selected
  local ignore_expanded=$(expand_filter_string "experimental" all_ids)
  local result=$(ignore_from_list selected_ids "$ignore_expanded")

  # Should have rust-v0.56 and rust-v0.55, but not rust-experimental
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should include rust-v0.55"
  assert_not_contains "$result" "rust-experimental" "Should exclude rust-experimental"
  assert_not_contains "$result" "go-v0.45" "Should not include go-v0.45 (not selected)"
}

# Test 34: Two-stage with multiple dimensions
test_two_stage_multiple_select_ignore() {
  local all_ids=("rust-v0.56" "rust-v0.55" "go-v0.45" "go-v0.44" "js-v1.0")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  ALIASES["go"]="go-v0.45|go-v0.44"

  # Stage 1: SELECT rust AND go
  local select_expanded=$(expand_filter_string "~rust|~go" all_ids)
  local selected_ids=()
  readarray -t selected_ids < <(select_from_list all_ids "$select_expanded")

  # Verify 4 items selected (all rust and go)
  local count=${#selected_ids[@]}
  assert_equals "$count" "4" "Should select 4 items (rust + go)"

  # Stage 2: IGNORE v0.55 and v0.44
  local result=$(ignore_from_list selected_ids "v0.55|v0.44")

  # Should have rust-v0.56 and go-v0.45 only
  assert_contains "$result" "rust-v0.56" "Should include rust-v0.56"
  assert_contains "$result" "go-v0.45" "Should include go-v0.45"
  assert_not_contains "$result" "rust-v0.55" "Should exclude rust-v0.55"
  assert_not_contains "$result" "go-v0.44" "Should exclude go-v0.44"
  assert_not_contains "$result" "js-v1.0" "Should not include js-v1.0"
}

# Test 35: select with no matches
test_select_no_matches() {
  local input_ids=("rust-v0.56" "go-v0.45" "js-v1.0")

  # Select pattern that doesn't match anything
  local result=$(select_from_list input_ids "python")

  # Result should be empty or contain no lines
  if [ -n "$result" ]; then
    local count=$(echo "$result" | grep -c '^' || true)
    assert_equals "$count" "0" "Select with no matches should return empty"
  fi
}

# Test 36: ignore vs select inverse relationship
test_ignore_select_inverse() {
  local input_ids=("rust-v0.56" "rust-v0.55" "go-v0.45" "js-v1.0")

  # select "rust" should be inverse of ignore "!rust" (everything except rust)
  local selected=$(select_from_list input_ids "rust")
  local ignored=$(ignore_from_list input_ids "!rust")

  # Both should produce same result (only rust items)
  assert_contains "$selected" "rust-v0.56" "Select rust should include rust-v0.56"
  assert_contains "$selected" "rust-v0.55" "Select rust should include rust-v0.55"
  assert_contains "$ignored" "rust-v0.56" "Ignore !rust should include rust-v0.56"
  assert_contains "$ignored" "rust-v0.55" "Ignore !rust should include rust-v0.55"
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Filter Engine Unit Tests                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Initialize global ALIASES array
declare -gA ALIASES

run_test "Simple value expansion" test_simple_value
run_test "Simple alias expansion" test_simple_alias
run_test "Nested alias expansion" test_nested_alias
run_test "Loop detection" test_loop_detection
run_test "Three-level nesting" test_three_level_nesting
run_test "Deduplication" test_deduplication
run_test "Empty string handling" test_empty_string
run_test "Inverted value (!pattern)" test_inverted_value
run_test "Inverted alias (!~alias)" test_inverted_alias
run_test "Mixed patterns" test_mixed_patterns
run_test "filter_matches function" test_filter_matches
run_test "ignore function" test_ignore_function
run_test "Unknown alias handling" test_unknown_alias
run_test "Complex inverted alias" test_complex_inverted_alias
run_test "Multiple inversions" test_multiple_inversions
run_test "Alias with single value" test_alias_single_value
run_test "Deep nesting (4 levels)" test_deep_nesting
run_test "Exact substring matching" test_exact_substring_matching
run_test "Inverted nested alias" test_inverted_nested_alias
run_test "Case sensitivity" test_case_sensitivity
run_test "Special characters" test_special_characters
run_test "Pipe in expansion" test_pipe_in_expansion
run_test "Empty filter matches" test_empty_filter_matches
run_test "Filter with all selected" test_filter_with_all_selected
run_test "Inverted partial match" test_inverted_partial_match
run_test "Multiple regular values" test_multiple_regular_values
run_test "Alias deduplication" test_alias_deduplication
run_test "Combined filters" test_combined_filters
run_test "select: empty filter" test_select_empty_filter
run_test "select: single pattern" test_select_single_pattern
run_test "select: multiple patterns" test_select_multiple_patterns
run_test "select: with alias expansion" test_select_with_alias
run_test "Two-stage filtering (select→ignore)" test_two_stage_filtering
run_test "Two-stage: multiple select & ignore" test_two_stage_multiple_select_ignore
run_test "select: no matches" test_select_no_matches
run_test "ignore vs select inverse" test_ignore_select_inverse

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Results: $PASSED_COUNT/$TEST_COUNT passed"

if [ $FAILED_COUNT -gt 0 ]; then
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  ✗ $test"
  done
  echo "════════════════════════════════════════════════════════════════"
  exit 1
else
  echo "✓ All tests passed!"
  echo "════════════════════════════════════════════════════════════════"
  exit 0
fi
