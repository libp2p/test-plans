# Bash Coding Style Guide

This guide documents the bash coding conventions and patterns used throughout the libp2p test framework. All examples are derived from actual code in `./lib`, `./perf`, `./transport`, and `./hole-punch`.

---

## Table of Contents

1. [File Structure and Shebang](#file-structure-and-shebang)
2. [Variable Naming Conventions](#variable-naming-conventions)
3. [Function Definitions](#function-definitions)
4. [Quoting and Safety](#quoting-and-safety)
5. [Array Operations with readarray](#array-operations-with-readarray)
6. [Command Substitution: Subshells vs Direct Calls](#command-substitution-subshells-vs-direct-calls)
7. [Name References (local -n)](#name-references-local--n)
8. [Error Handling](#error-handling)
9. [Conditional Expressions](#conditional-expressions)
10. [String Operations](#string-operations)
11. [File Locking](#file-locking)
12. [Parallelization](#parallelization)

---

## File Structure and Shebang

### Standard Header

All bash scripts start with shebang and descriptive comment:

```bash
#!/bin/bash
# Brief description of what this script does
```

**Example** (from `lib/lib-filter-engine.sh`):
```bash
#!/bin/bash
# Common filter engine for test/baseline/relay/router filtering
# Provides recursive alias expansion with loop detection, proper inversion, and deduplication
```

### Set Options

Use `set` to configure bash behavior at the top of scripts:

```bash
set -ueo pipefail
```

- `-u`: Error on undefined variables
- `-e`: Exit on error (use carefully, often omitted in main scripts)
- `-o pipefail`: Pipelines fail if any command fails

**Example** (from `perf/lib/generate-tests.sh`):
```bash
#!/bin/bash
# Generate test matrix from ${IMAGES_YAML} with filtering

set -ueo pipefail

trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR
```

### Script Directory Detection

Get the directory containing the current script:

```bash
_this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**Example** (from `lib/lib-filter-engine.sh:7-8`):
```bash
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_this_script_dir}/lib-output-formatting.sh"
fi
```

---

## Variable Naming Conventions

### Case Conventions

**SCREAMING_SNAKE_CASE** for:
- Global variables
- Environment variables
- Constants
- Configuration values

```bash
TEST_IGNORE="${TEST_IGNORE:-}"
IMAGES_YAML="${IMAGES_YAML:-./images.yaml}"
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
WORKER_COUNT="${WORKER_COUNT:-1}"
DEBUG="${DEBUG:-false}"
```

Note: The test framework uses `get_cpu_count()` from `lib/lib-host-os.sh` for cross-platform CPU detection (macOS uses `sysctl`, Linux/WSL uses `nproc`).

**snake_case** for:
- Local variables
- Function parameters
- Loop variables

```bash
local test_name="rust-v0.56 x rust-v0.56 (tcp, noise, yamux)"
local dialer_id="rust-v0.56"
local listener_id="rust-v0.56"
```

### Underscore Prefixes

Use leading underscore for:
- Private/internal functions
- Internal/temporary variables

```bash
_resolve_alias() {
  local alias_name="${1}"
  # ...
}

_this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Variable Initialization with Defaults

Use parameter expansion for defaults:

```bash
# Simple default
IMAGES_YAML="${IMAGES_YAML:-./images.yaml}"

# Command substitution default
WORKER_COUNT="${WORKER_COUNT:-$(get_cpu_count)}"

# Empty string default (variable may not be set)
TEST_IGNORE="${TEST_IGNORE:-}"
```

**Example** (from `lib/lib-common-init.sh:23-33`):
```bash
# Files
IMAGES_YAML="${IMAGES_YAML:-${TEST_ROOT}/images.yaml}"

# Paths
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_RUN_DIR="${TEST_RUN_DIR:-${CACHE_DIR}/test-run}"

# Common filtering variables
TEST_IGNORE="${TEST_IGNORE:-}"
TRANSPORT_IGNORE="${TRANSPORT_IGNORE:-}"
SECURE_IGNORE="${SECURE_IGNORE:-}"
MUXER_IGNORE="${MUXER_IGNORE:-}"
```

### Array Variables

Arrays use same naming conventions but are declared with `()`:

```bash
# Global arrays
readarray -t FAILED_TESTS < <(...)
all_image_ids=()
filtered_image_ids=()

# Local arrays
local -a result_parts=()
local parts=()
```

---

## Function Definitions

### Function Declaration Style

Use function name followed by parentheses (no `function` keyword):

```bash
# Good
compute_test_key() {
  local test_name="$1"
  # ...
}

# Avoid
function compute_test_key {
  # ...
}
```

### Function Documentation

Document complex functions with comments:

```bash
# Compute cache key for the test run from images.yaml + any other parameters
#
# Args:
#   $1: images_yaml - Path to images.yaml file
#   $@: Additional parameters to include in hash
# Returns:
#   8-character hexadecimal string
# Usage:
#   TEST_RUN_KEY=$(compute_test_run_key "$IMAGES_YAML" "$TEST_IGNORE" "$DEBUG")
compute_test_run_key() {
  local images_yaml="$1"
  shift
  # ...
}
```

**Example** (from `lib/lib-test-caching.sh:11-34`):
```bash
# Compute cache key for the test run from images.yaml + any other parameters
#
# Usage:
# compute_test_run_key "images.yaml"
compute_test_run_key() {
  local images_yaml="$1"
  shift

  # 1. Load contents of $images_yaml file
  local contents=$(<"${images_yaml}")

  # 2. Remaining arguments joined with '||'
  local args
  if (( $# == 0 )); then
    args=""
  else
    args=$(printf '%s\n' "$@" | paste -sd '|' -)
  fi

  # 3. Calculate the hash of both
  local hash=$(printf '%s' "${contents}${args}" | sha256sum | cut -d ' ' -f1)

  echo "${hash:0:8}"
}
```

### Function Parameters

Always use `local` for function parameters:

```bash
my_function() {
  local param1="$1"
  local param2="$2"
  local optional_param="${3:-default_value}"

  # Function body
}
```

Use `shift` to handle variable arguments:

```bash
compute_test_run_key() {
  local images_yaml="$1"
  shift  # Remove first argument, $@ now contains remaining args

  # Process remaining arguments
  local args=$(printf '%s\n' "$@" | paste -sd '|' -)
}
```

---

## Quoting and Safety

### Always Quote Variables

**Rule**: Quote all variable expansions unless you explicitly want word splitting:

```bash
# Good
docker build -t "${image_name}" "${build_path}"
if [ -f "${COMPOSE_FILE}" ]; then
  rm "${COMPOSE_FILE}"
fi

# Bad (can break with spaces)
docker build -t $image_name $build_path
if [ -f $COMPOSE_FILE ]; then
  rm $COMPOSE_FILE
fi
```

### Special Cases: Don't Quote When Word Splitting Is Intended

Some cases require unquoted variables for word splitting:

```bash
# Intentionally unquoted for word splitting
for transport in ${common_transports}; do
  # common_transports is space-separated: "tcp ws quic-v1"
done

# Docker compose command (WARNING: must not be quoted!)
${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up
# DOCKER_COMPOSE_CMD might be "docker compose" or "podman-compose"
```

**Example** (from `perf/lib/run-single-test.sh:142-145`):
```bash
# WARNING: Do NOT put quotes around this because the command has two parts
if timeout "${TEST_TIMEOUT}" ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up \
  --exit-code-from dialer --abort-on-container-exit >> "${LOG_FILE}" 2>&1; then
```

---

## Array Operations with readarray

### What is readarray?

`readarray` (also called `mapfile`) reads lines from stdin into an array. It's extremely useful for capturing command output into arrays.

**Syntax**:
```bash
readarray -t ARRAY_NAME < <(command)
```

- `-t`: Remove trailing newlines from each line
- `< <(...)`: Process substitution (creates a file descriptor from command output)

### Basic Usage

**Example 1**: Get all implementation IDs from YAML:

```bash
readarray -t all_image_ids < <(get_entity_ids "implementations")
```

This is equivalent to:
```bash
all_image_ids=()
while IFS= read -r line; do
  all_image_ids+=("$line")
done < <(get_entity_ids "implementations")
```

But much more concise!

**Example 2**: Get failed test names (from `perf/run.sh:738`):

```bash
readarray -t FAILED_TESTS < <(
  yq eval '.tests[] | select(.status == "fail") | .name' "${TEST_PASS_DIR}/results.yaml" 2>/dev/null || true
)

# Now iterate through failed tests
for test_name in "${FAILED_TESTS[@]}"; do
  echo "  ✗ ${test_name}"
done
```

### Multiple readarray Calls

Often used to load different data sets:

**Example** (from `perf/run.sh:455-474`):
```bash
# Load selected baseline tests
readarray -t selected_baseline_tests < <(
  get_entity_ids "baselines" "${TEST_PASS_DIR}/test-matrix.yaml"
)

# Load ignored baseline tests
readarray -t ignored_baseline_tests < <(
  get_entity_ids "ignoredBaselines" "${TEST_PASS_DIR}/test-matrix.yaml"
)

# Load selected main tests
readarray -t selected_main_tests < <(
  get_entity_ids "tests" "${TEST_PASS_DIR}/test-matrix.yaml"
)

# Load ignored main tests
readarray -t ignored_main_tests < <(
  get_entity_ids "ignoredTests" "${TEST_PASS_DIR}/test-matrix.yaml"
)

# Now we have 4 separate arrays we can work with
```

### Checking Array Length

After using `readarray`, check if array is empty:

```bash
readarray -t selected_tests < <(get_entity_ids "tests")

if [ ${#selected_tests[@]} -eq 0 ]; then
  echo "No tests selected"
  exit 0
fi

echo "Running ${#selected_tests[@]} tests..."
```

### Iterating Arrays from readarray

```bash
# By index
for ((i=0; i<${#selected_tests[@]}; i++)); do
  echo "Test $i: ${selected_tests[$i]}"
done

# By value
for test_name in "${selected_tests[@]}"; do
  echo "Running: ${test_name}"
done
```

---

## Command Substitution: Subshells vs Direct Calls

### Direct Function Call

**When**: Function modifies current shell state (variables, working directory, etc.)

**Syntax**: Just call the function

```bash
# Direct call - function runs in current shell
init_common_variables

# Variables set by the function are available
echo "${IMAGES_YAML}"  # Set by init_common_variables
```

**Example** (from `perf/run.sh:93-94`):
```bash
# Initialize common variables
init_common_variables

# Variables are now set in this shell
IMAGES_YAML="${IMAGES_YAML}"  # Available!
```

### Subshell with Command Substitution

**When**: Capture function output without affecting current shell

**Syntax**: `VAR=$(function_name args)`

```bash
# Subshell - function runs in child process
TEST_RUN_KEY=$(compute_test_run_key "$IMAGES_YAML" "$TEST_IGNORE")

# Function's output is captured, but any variables it sets are lost
# Only the final echo/printf is captured
```

**Example** (from `lib/lib-test-caching.sh:15-34`):
```bash
compute_test_run_key() {
  local images_yaml="$1"
  shift

  local contents=$(<"${images_yaml}")
  local args=$(printf '%s\n' "$@" | paste -sd '|' -)
  local hash=$(printf '%s' "${contents}${args}" | sha256sum | cut -d ' ' -f1)

  # This echo is what gets captured
  echo "${hash:0:8}"
}

# Usage - captures the echo output
TEST_RUN_KEY=$(compute_test_run_key "$IMAGES_YAML" "$TEST_IGNORE")
```

### Nested Command Substitution

Can nest multiple levels:

```bash
# Get count of tests
TEST_COUNT=$(yq eval '.tests | length' "${TEST_PASS_DIR}/test-matrix.yaml")

# Get test name using captured count
for ((i=0; i<TEST_COUNT; i++)); do
  test_name=$(yq eval ".tests[${i}].id" "${TEST_PASS_DIR}/test-matrix.yaml")
  echo "Test $i: ${test_name}"
done
```

### Command Substitution in Variable Assignment

**Example** (from `transport/run.sh:594-599`):
```bash
cat > "${TEST_PASS_DIR}/results.yaml" <<EOF
metadata:
  testPass: ${TEST_PASS_NAME}
  startedAt: $(date -d @"${TEST_START_TIME}" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -r "${TEST_START_TIME}" -u +%Y-%m-%dT%H:%M:%SZ)
  completedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  duration: ${TEST_DURATION}s
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: ${WORKER_COUNT}
EOF
```

### Process Substitution

Different from command substitution - creates a temporary file descriptor:

```bash
# Process substitution: <(command)
# Creates /dev/fd/N that reads from command output
readarray -t test_ids < <(get_entity_ids "tests")

# Useful for multiple inputs to a command
diff <(sort file1.txt) <(sort file2.txt)
```

**Why use `< <(...)` instead of `$(...)` for readarray?**

```bash
# Wrong - this doesn't work!
readarray -t tests $(get_entity_ids "tests")

# Right - process substitution creates a file to read from
readarray -t tests < <(get_entity_ids "tests")
```

---

## Name References (local -n)

### What are Name References?

`local -n` creates a name reference (like a pointer) to another variable. Useful for passing arrays and avoiding global variables.

**Syntax**:
```bash
local -n ref_name="variable_name"
```

### Basic Example

**Example** (from `lib/lib-filter-engine.sh:35-69`):
```bash
_resolve_alias() {
  local alias_name="${1}"
  local -n processed_aliases_ref="${2}"  # Name reference to array
  local -n value_ref="${3}"              # Name reference to string

  # Modify the referenced variable directly
  value_ref="${ALIASES[${alias_name}]:-}"

  # Append to the referenced array
  processed_aliases_ref="${processed_aliases_ref} ${alias_name}"

  return 0
}

# Usage
processed_aliases=""
resolved_value=""
_resolve_alias "rust" processed_aliases resolved_value

# processed_aliases and resolved_value are now modified
echo "Processed: ${processed_aliases}"
echo "Value: ${resolved_value}"
```

### Array Name References

Pass arrays to functions by reference:

**Example** (from `lib/lib-filter-engine.sh:71-75`):
```bash
_expand_recursive() {
  local filter_string="${1}"
  local -n all_names_ref="${2}"        # Array reference
  local -n processed_aliases_ref="${3}"  # String reference
  local -n result_parts_ref="${4}"      # Array reference

  # Can read from referenced arrays
  for name in "${all_names_ref[@]}"; do
    # ...
  done

  # Can append to referenced arrays
  result_parts_ref+=("new_element")
}

# Usage
all_names=("rust-v0.56" "go-v0.45")
processed_aliases=""
result_parts=()

_expand_recursive "~rust" all_names processed_aliases result_parts

# result_parts array is now modified
```

### Why Use Name References?

**Without name references** - need global variables or complex return handling:
```bash
# Bad - uses global variable
RESULT=""

get_value() {
  RESULT="some value"  # Modifies global
}

get_value
echo "${RESULT}"
```

**With name references** - clean parameter passing:
```bash
# Good - uses name reference
get_value() {
  local -n result_ref="${1}"
  result_ref="some value"  # Modifies caller's variable
}

my_result=""
get_value my_result
echo "${my_result}"
```

### Common Pattern: Multiple Return Values

**Example**:
```bash
get_test_info() {
  local test_index="${1}"
  local -n dialer_ref="${2}"
  local -n listener_ref="${3}"
  local -n transport_ref="${4}"

  dialer_ref=$(yq eval ".tests[${test_index}].dialer.id" test-matrix.yaml)
  listener_ref=$(yq eval ".tests[${test_index}].listener.id" test-matrix.yaml)
  transport_ref=$(yq eval ".tests[${test_index}].transport" test-matrix.yaml)
}

# Usage
dialer=""
listener=""
transport=""
get_test_info 0 dialer listener transport

echo "Test: ${dialer} x ${listener} (${transport})"
```

---

## Error Handling

### Exit Codes

- 0 = Success
- Non-zero = Error

```bash
if docker build -t "${image_name}" "${build_path}"; then
  echo "Build successful"
else
  echo "Build failed"
  return 1
fi
```

### Safe Command Execution

Use `|| true` to prevent exits:

```bash
# Don't exit if grep finds nothing
FAILED=$(grep -c "status: fail" results.yaml || true)

# Don't exit if file doesn't exist
readarray -t TESTS < <(yq eval '.tests[]' results.yaml 2>/dev/null || true)
```

### Trap for Cleanup

**Example** (from `perf/lib/generate-tests.sh:10`):
```bash
trap 'echo "ERROR in generate-tests.sh at line $LINENO: Command exited with status $?" >&2' ERR
```

---

## Conditional Expressions

### File Tests

```bash
if [ -f "${file_path}" ]; then    # File exists
if [ -d "${dir_path}" ]; then     # Directory exists
if [ -r "${file_path}" ]; then    # File is readable
if [ -w "${file_path}" ]; then    # File is writable
if [ -z "${string}" ]; then       # String is empty
if [ -n "${string}" ]; then       # String is not empty
```

### Numeric Comparisons

```bash
if [ "${count}" -eq 0 ]; then     # Equal
if [ "${count}" -ne 0 ]; then     # Not equal
if [ "${count}" -gt 0 ]; then     # Greater than
if [ "${count}" -lt 10 ]; then    # Less than
if [ "${count}" -ge 5 ]; then     # Greater or equal
if [ "${count}" -le 20 ]; then    # Less or equal
```

### String Comparisons

```bash
if [ "${status}" = "pass" ]; then      # String equal
if [ "${status}" != "fail" ]; then     # String not equal
if [ "${status}" == "pass" ]; then     # Also works (bash-specific)
```

### Pattern Matching

```bash
# Case statement
case "${source_type}" in
  local)
    build_from_local "$YAML_FILE"
    ;;
  github)
    build_from_github "$YAML_FILE"
    ;;
  browser)
    build_browser_image "$YAML_FILE"
    ;;
  *)
    echo "Unknown source type: ${source_type}"
    return 1
    ;;
esac

# Regex matching
if [[ "${part}" =~ ^!~(.+)$ ]]; then
  # Captured group in ${BASH_REMATCH[1]}
  local alias_name="${BASH_REMATCH[1]}"
fi
```

### Boolean Variables

Use strings "true" and "false", not 0/1:

```bash
DEBUG="${DEBUG:-false}"

if [ "${DEBUG}" = "true" ]; then
  echo "Debug mode enabled"
fi
```

---

## String Operations

### Concatenation

```bash
# Simple concatenation
full_name="${first_name} ${last_name}"

# Building paths
image_name="${TEST_TYPE}-implementations-${impl_id}"
```

### Substring Extraction

```bash
# First 8 characters
short_hash="${hash:0:8}"

# Remove prefix
part="${part#\\}"  # Remove leading backslash

# Remove suffix
filename="${path%.*}"  # Remove extension
```

### String Replacement

```bash
# Replace first occurrence
new_string="${old_string/search/replace}"

# Replace all occurrences
new_string="${old_string//search/replace}"

# Example: slug from test name
TEST_SLUG=$(echo "${TEST_NAME}" | sed 's/[^a-zA-Z0-9-]/_/g')
```

### Trimming

```bash
# Remove leading/trailing whitespace
trimmed=$(echo "${string}" | xargs)
```

---

## File Locking

### Why File Locking?

When multiple processes write to the same file, use `flock` to prevent corruption.

### Basic Pattern

```bash
(
  flock -x 200  # Exclusive lock on fd 200
  # Critical section - only one process at a time
  echo "data" >> shared_file.txt
) 200>/tmp/lockfile.lock
```

### Real Example: Parallel Test Result Writing

**Example** (from `perf/lib/run-single-test.sh:196-207`):
```bash
# Multiple tests running in parallel, all writing to same file
(
  flock -x 200
  cat >> "${RESULTS_FILE}" <<EOF
  - name: ${TEST_NAME}
    dialer: ${DIALER_ID}
    listener: ${LISTENER_ID}
    status: $([ "${EXIT_CODE}" -eq 0 ] && echo "pass" || echo "fail")
    duration: ${TEST_DURATION}s
EOF
) 200>/tmp/results.lock
```

### File Lock Pattern: Message Printing

**Example** (from `transport/run.sh:534-537`):
```bash
# Serialize the message printing using flock (prevents interleaved output)
(
  flock -x 200
  print_message "[$((index + 1))/${TEST_COUNT}] ${name}...${result}"
) 200>/tmp/transport-test-output.lock
```

**Why?** Without locking, parallel processes would interleave output:
```
Test 1...Test 2...
[SUCCESS]Test 3...
[FAILED][SUCCESS]
```

With locking:
```
Test 1... [SUCCESS]
Test 2... [FAILED]
Test 3... [SUCCESS]
```

---

## Parallelization

### Pattern 1: Sequential Execution

**Use case**: Perf tests (accurate measurements require sequential execution)

**Pattern**:
```bash
WORKER_COUNT=1

for ((i=0; i<TEST_COUNT; i++)); do
  bash "${SCRIPT_DIR}/run-single-test.sh" "${i}"
done
```

**Example** (from `perf/run.sh:607-625`):
```bash
for ((i=0; i<TEST_COUNT; i++)); do
  # Check for shutdown
  if [ "${SHUTDOWN}" == "true" ]; then
    break
  fi

  # Get test name
  test_name=$(yq eval ".tests[${i}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  # Show progress
  if [ "${DEBUG:-false}" == "true" ]; then
    print_message "[$((i + 1))/${TEST_COUNT}] ${test_name}..."
  else
    echo_message "[$((i + 1))/${TEST_COUNT}] ${test_name}..."
  fi

  # Run test
  if bash "${SCRIPT_DIR}/run-single-test.sh" "${i}" "tests" "${TEST_RESULTS_FILE}"; then
    echo "[SUCCESS]"
  else
    echo "[FAILED]"
  fi
done
```

### Pattern 2: Parallel with xargs

**Use case**: Transport tests (maximize throughput)

**Pattern**:
```bash
WORKER_COUNT=$(get_cpu_count)

run_test() {
  local index="${1}"
  # Test logic here
}

export -f run_test
seq 0 $((TEST_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_test {}'
```

**Complete Example** (from `transport/run.sh:516-548`):
```bash
# Define function to run in parallel
run_test() {
  local index="${1}"
  local name=$(yq eval ".tests[${index}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

  # Source libraries in subshell
  source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"

  # Run test
  if bash "${SCRIPT_DIR}/run-single-test.sh" "${index}" "tests" "${TEST_PASS_DIR}/results.yaml.tmp"; then
    result="[SUCCESS]"
    exit_code=0
  else
    result="[FAILED]"
    exit_code=1
  fi

  # Serialize message printing with flock
  (
    flock -x 200
    print_message "[$((index + 1))/${TEST_COUNT}] ${name}...${result}"
  ) 200>/tmp/transport-test-output.lock

  return ${exit_code}
}

# Export function and variables for subshells
export TEST_COUNT
export -f run_test

# Run tests in parallel
seq 0 $((TEST_COUNT - 1)) | xargs -P "${WORKER_COUNT}" -I {} bash -c 'run_test {}' || true
```

**Key points**:
- Function must be exported: `export -f run_test`
- Variables must be exported: `export TEST_COUNT`
- Use `|| true` to continue despite failures
- Use flock to serialize output

### Pattern 3: Parallel with Background Jobs (jobs -r)

**Alternative pattern** using bash job control:

```bash
WORKER_COUNT=$(get_cpu_count)

for ((i=0; i<TEST_COUNT; i++)); do
  # Run in background
  bash "${SCRIPT_DIR}/run-single-test.sh" "${i}" &

  # Limit concurrent jobs
  while [ $(jobs -r | wc -l) -ge ${WORKER_COUNT} ]; do
    sleep 0.1
  done
done

# Wait for all background jobs to finish
wait
```

**How it works**:
1. `&` runs command in background
2. `jobs -r` lists running jobs
3. `wc -l` counts them
4. Loop waits until a slot is free
5. `wait` ensures all jobs complete before continuing

**Example** (conceptual from `docs/overall-flow.md`):
```bash
for ((i=0; i<TEST_COUNT; i++)); do
  bash "${SCRIPT_DIR}/run-single-test.sh" "$i" "tests" "$RESULTS_FILE" &

  # Limit concurrent jobs
  while [ $(jobs -r | wc -l) -ge $WORKER_COUNT ]; do
    sleep 0.1
  done
done
wait  # Wait for all background jobs
```

### Pattern Comparison

| Pattern | Pros | Cons | Use Case |
|---------|------|------|----------|
| **Sequential** | Simple, predictable order | Slow | Perf tests, debugging |
| **xargs -P** | Built-in parallelization, clean | Can't easily limit by CPU | Transport tests |
| **Background jobs** | Fine control, standard bash | More complex | Custom parallelization |

### Parallel Execution Considerations

**1. File Locking**:
```bash
# Always lock when writing to shared files
(
  flock -x 200
  echo "data" >> shared_file.txt
) 200>/tmp/lockfile.lock
```

**2. Resource Limits**:
```bash
# Respect system resources
WORKER_COUNT=$(get_cpu_count)

# Or limit explicitly
WORKER_COUNT=4
```

**3. Error Handling**:
```bash
# Don't let one failure stop all tests
run_test || true

# Or with xargs
seq 0 9 | xargs -P 4 -I {} bash -c 'test_command {}' || true
```

**4. Progress Reporting**:
```bash
# Serialize output to avoid interleaving
(
  flock -x 200
  echo "Test ${i} complete"
) 200>/tmp/output.lock
```

---

## Summary

This bash style guide captures the conventions used throughout the libp2p test framework:

- **File structure**: Shebang, set options, trap handlers
- **Variables**: SCREAMING_SNAKE_CASE for globals, snake_case for locals
- **Functions**: Document complex functions, use local for parameters
- **Arrays**: Use readarray for capturing output, name references for passing
- **Quoting**: Always quote variables except when word splitting is intended
- **Subshells**: Use `$()` to capture output, direct calls to modify current shell
- **Parallelization**: Sequential for accuracy, xargs/background jobs for speed

Following these patterns ensures consistency across all test suites and makes the codebase easier to maintain and extend.
