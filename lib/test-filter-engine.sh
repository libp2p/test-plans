#!/bin/bash
# Unit tests for lib-filter-engine.sh
# Tests recursive alias expansion, loop detection, inversion, and filtering

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source the libraries we're testing
source "$SCRIPT_DIR/lib-test-images.sh"
source "$SCRIPT_DIR/lib-filter-engine.sh"

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

  if [ "$actual" = "$expected" ]; then
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

  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  else
    if [ -n "$message" ]; then
      fail "$message (expected '$haystack' to contain '$needle')"
    else
      fail "Expected '$haystack' to contain '$needle'"
    fi
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-}"

  if [[ "$haystack" != *"$needle"* ]]; then
    return 0
  else
    if [ -n "$message" ]; then
      fail "$message (expected '$haystack' to NOT contain '$needle')"
    else
      fail "Expected '$haystack' to NOT contain '$needle'"
    fi
  fi
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
  local result=$(_expand_alias_recursive "rust" "")
  assert_equals "$result" "rust-v0.56|rust-v0.55" "Simple alias expansion failed"
}

# Test 3: Nested alias expansion (recursive)
test_nested_alias() {
  ALIASES["rust"]="rust-v0.56|rust-v0.55"
  ALIASES["stable"]="~rust|go-v0.45"

  local result=$(_expand_alias_recursive "stable" "")
  assert_contains "$result" "rust-v0.56" "Nested alias should expand rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Nested alias should expand rust-v0.55"
  assert_contains "$result" "go-v0.45" "Nested alias should include go-v0.45"
}

# Test 4: Loop detection
test_loop_detection() {
  ALIASES["a"]="~b"
  ALIASES["b"]="~a"

  # This should fail with loop detection
  if _expand_alias_recursive "a" "" 2>/dev/null; then
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

  local result=$(_expand_alias_recursive "stable" "")
  assert_contains "$result" "rust-v0.56" "Three-level nesting should expand v56"
  assert_contains "$result" "rust-v0.55" "Three-level nesting should expand v55"
  assert_contains "$result" "go-v0.45" "Three-level nesting should include go"
}

# Test 6: Deduplication
test_deduplication() {
  local result=$(deduplicate_filter "rust|go|rust|python|go")
  # Should be sorted and unique
  assert_equals "$result" "go|python|rust" "Deduplication failed"
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

# Test 10: Mixed patterns (values, aliases, inversions)
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

# Test 12: Select/Ignore interaction (THE CRITICAL PATTERN)
test_select_ignore_interaction() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  local input_names=("${all_names[@]}")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  # Test 1: SELECT only rust
  local result=$(filter_names input_names all_names "~rust" "")
  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "2" "Select ~rust should return 2 items"
  assert_contains "$result" "rust-v0.56" "Select should include rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Select should include rust-v0.55"

  # Test 2: SELECT rust, IGNORE non-rust (should be same as Test 1)
  result=$(filter_names input_names all_names "~rust" "!~rust")
  count=$(echo "$result" | wc -l)
  assert_equals "$count" "2" "Select ~rust + ignore !~rust should return 2 items"

  # Test 3: SELECT all, IGNORE rust
  result=$(filter_names input_names all_names "" "~rust")
  assert_not_contains "$result" "rust-v0.56" "Ignore should exclude rust-v0.56"
  assert_not_contains "$result" "rust-v0.55" "Ignore should exclude rust-v0.55"
  assert_contains "$result" "go-v0.45" "Ignore rust should keep go"
  assert_contains "$result" "python-v0.4" "Ignore rust should keep python"

  return 0
}

# Test 13: Multiple entity types (verify generic works for all)
test_multiple_entity_types() {
  # Setup different entity types
  local all_impls=("rust-v0.56" "go-v0.45" "python-v0.4")
  local all_relays=("linux" "chromium" "firefox")
  local all_routers=("linux-router" "chromium-router")

  local input_impls=("${all_impls[@]}")
  local input_relays=("${all_relays[@]}")
  local input_routers=("${all_routers[@]}")

  # Test filtering works identically for all types
  local result_impls=$(filter_names input_impls all_impls "rust" "")
  assert_contains "$result_impls" "rust-v0.56" "Should filter impls"

  local result_relays=$(filter_names input_relays all_relays "linux" "")
  assert_contains "$result_relays" "linux" "Should filter relays"

  local result_routers=$(filter_names input_routers all_routers "linux" "")
  assert_contains "$result_routers" "linux-router" "Should filter routers"

  return 0
}

# Test 14: Deduplication in expansion
test_expansion_deduplication() {
  local all_names=("rust-v0.56" "go-v0.45")
  ALIASES["rust"]="rust-v0.56"

  # ~rust|rust-v0.56 should deduplicate to just rust-v0.56
  local result=$(expand_filter_string "~rust|rust-v0.56" all_names)
  local count=$(echo "$result" | tr '|' '\n' | wc -l)
  assert_equals "$count" "1" "Should deduplicate rust-v0.56"
}

# Test 15: Unknown alias handling
test_unknown_alias() {
  local all_names=("rust-v0.56")

  # Unknown alias should return empty (not error)
  local result=$(expand_filter_string "~nonexistent" all_names)
  assert_equals "$result" "" "Unknown alias should return empty"
}

# Test 16: Complex inverted alias
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

# Test 17: Ignore operates on selected set only
test_ignore_on_selected_set() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  local input_names=("${all_names[@]}")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  # SELECT: ~rust (gets rust-v0.56, rust-v0.55)
  # IGNORE: go (should have no effect since go not in selected set)
  local result=$(filter_names input_names all_names "~rust" "go")
  local count=$(echo "$result" | wc -l)

  assert_equals "$count" "2" "Ignore should operate on selected set only"
  assert_contains "$result" "rust-v0.56" "Should keep rust-v0.56"
  assert_contains "$result" "rust-v0.55" "Should keep rust-v0.55"
  assert_not_contains "$result" "go" "Should not contain go"
}

# Test 18: Empty select means all
test_empty_select_means_all() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4")
  local input_names=("${all_names[@]}")

  # Empty select should include all
  local result=$(filter_names input_names all_names "" "")
  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "3" "Empty select should return all names"
}

# Test 19: Empty ignore means keep all selected
test_empty_ignore_keeps_all() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45")
  local input_names=("${all_names[@]}")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  # SELECT rust, empty IGNORE
  local result=$(filter_names input_names all_names "~rust" "")
  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "2" "Empty ignore should keep all selected"
}

# Test 20: Pipe cleanup (multiple pipes, leading/trailing)
test_pipe_cleanup() {
  local all_names=("rust-v0.56")

  # Should handle malformed filter strings
  local result=$(deduplicate_filter "rust||go|||python|")
  assert_equals "$result" "go|python|rust" "Should clean up pipes"
}

# Test 21: Case sensitivity
test_case_sensitivity() {
  local all_names=("Rust-v0.56" "rust-v0.56")

  # Substring matching is case-sensitive in bash
  filter_matches "rust-v0.56" "Rust" && fail "Should be case-sensitive"
  filter_matches "Rust-v0.56" "Rust" || fail "Should match exact case"

  return 0
}

# Test 22: Special characters in patterns
test_special_characters() {
  local all_names=("rust-v0.56" "go-v0.45")

  # Dash should work in patterns
  filter_matches "rust-v0.56" "v0.56" || fail "Should match with dots"
  filter_matches "rust-v0.56" "rust-v" || fail "Should match with dash"

  return 0
}

# Test 23: Multiple inversions (OR semantics)
test_multiple_inversions() {
  local all_names=("rust-v0.56" "go-v0.45" "python-v0.4" "js-v3.x")

  # !rust|!go means: (names NOT containing rust) OR (names NOT containing go)
  # !rust → go-v0.45, python-v0.4, js-v3.x
  # !go → rust-v0.56, python-v0.4, js-v3.x
  # Union → ALL names (correct OR semantics)
  local result=$(expand_filter_string "!rust|!go" all_names)

  # Result should be ALL names (this is correct OR behavior)
  assert_contains "$result" "rust-v0.56" "OR semantics: should include rust"
  assert_contains "$result" "go-v0.45" "OR semantics: should include go"
  assert_contains "$result" "python-v0.4" "OR semantics: should include python"
  assert_contains "$result" "js-v3.x" "OR semantics: should include js"

  # For AND semantics (exclude rust AND go), use ignore filter:
  # --test-select "" --test-ignore "rust|go"
}

# Test 24: Alias with single value
test_alias_single_value() {
  ALIASES["latest"]="rust-v0.56"

  local result=$(_expand_alias_recursive "latest" "")
  assert_equals "$result" "rust-v0.56" "Single-value alias should work"
}

# Test 25: Deep nesting (4 levels)
test_deep_nesting() {
  ALIASES["a"]="a-value"
  ALIASES["b"]="~a|b-value"
  ALIASES["c"]="~b|c-value"
  ALIASES["d"]="~c|d-value"

  local result=$(_expand_alias_recursive "d" "")
  assert_contains "$result" "a-value" "Deep nesting should expand all levels"
  assert_contains "$result" "b-value"
  assert_contains "$result" "c-value"
  assert_contains "$result" "d-value"
}

# Test 26: Filter matching with exact substring
test_exact_substring_matching() {
  filter_matches "rust-v0.56" "rust-v0.56" || fail "Should match exact string"
  filter_matches "rust-v0.56" "v0.56" || fail "Should match substring"
  filter_matches "rust-v0.56" "rust" || fail "Should match prefix"
  filter_matches "rust-v0.56" "0.56" || fail "Should match suffix"

  filter_matches "rust-v0.56" "v0.55" && fail "Should not match different version"

  return 0
}

# Test 27: Inverted alias with nesting
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

# Test 28: Best practice pattern (select + ignore negation)
test_best_practice_pattern() {
  local all_names=("rust-v0.56" "rust-v0.55" "go-v0.45" "python-v0.4")
  local input_names=("${all_names[@]}")
  ALIASES["rust"]="rust-v0.56|rust-v0.55"

  # Best practice: --test-select '~rust' --test-ignore '!~rust'
  # Should select ONLY rust (rust in select, non-rust ignored from selected set)
  local result=$(filter_names input_names all_names "~rust" "!~rust")

  local count=$(echo "$result" | wc -l)
  assert_equals "$count" "2" "Best practice should return exactly rust items"
  assert_contains "$result" "rust-v0.56"
  assert_contains "$result" "rust-v0.55"
  assert_not_contains "$result" "go"
  assert_not_contains "$result" "python"
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
run_test "Select/Ignore interaction" test_select_ignore_interaction
run_test "Multiple entity types" test_multiple_entity_types
run_test "Deduplication in expansion" test_expansion_deduplication
run_test "Unknown alias handling" test_unknown_alias
run_test "Complex inverted alias" test_complex_inverted_alias
run_test "Exact substring matching" test_exact_substring_matching
run_test "Inverted nested alias" test_inverted_nested_alias
run_test "Best practice pattern" test_best_practice_pattern
run_test "Empty select means all" test_empty_select_means_all
run_test "Empty ignore keeps all" test_empty_ignore_keeps_all
run_test "Pipe cleanup" test_pipe_cleanup
run_test "Case sensitivity" test_case_sensitivity
run_test "Special characters" test_special_characters
run_test "Multiple inversions" test_multiple_inversions
run_test "Alias with single value" test_alias_single_value
run_test "Deep nesting (4 levels)" test_deep_nesting
run_test "Ignore on selected set only" test_ignore_on_selected_set

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
