# inputs.yaml Schema Documentation

## Overview

The `inputs.yaml` file is a YAML configuration file that captures all test run parameters for reproducibility. It is automatically generated at the start of each test run and stored in the test pass directory (`$TEST_PASS_DIR/inputs.yaml`).

**Purpose:**
- **Reproducibility**: Preserves exact test configuration for re-running tests with identical settings
- **Auditability**: Documents what parameters were used for a specific test run
- **Snapshot Support**: Enables test pass snapshots to be re-executed in different environments

## File Location

```
/srv/cache/test-run/<test-pass-name>/inputs.yaml
```

Example:
```
/srv/cache/test-run/perf-e5b6ea57-185931-28-12-2025/inputs.yaml
```

## Schema

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `testType` | string | Yes | Type of test suite: `transport`, `perf`, or `hole-punch` |
| `commandLineArgs` | array | Yes | Original command-line arguments passed to the test runner |
| `environmentVariables` | object | Yes | Key-value pairs of all relevant environment variables |

### Common Environment Variables

These variables are included for all test types:

**Paths and Settings:**

| Variable | Description |
|----------|-------------|
| `IMAGES_YAML` | The images YAML file used to run the tests (default: `./images.yaml`) |
| `CACHE_DIR` | Cache directory path (default: `/srv/cache`) |
| `TEST_RUN_DIR` | Test run directory path (default: `/srv/cache/test-run`) |
| `SCRIPT_DIR` | Test-specific library scripts directory path |
| `SCRIPT_LIB_DIR` | Shared library scripts directory path |
| `DEBUG` | Debug mode flag (`true` or `false`) |
| `WORKER_COUNT` | Number of parallel test workers |
| `FORCE_MATRIX_REBUILD` | Force test matrix regeneration flag |
| `FORCE_IMAGE_REBUILD` | Force Docker image rebuild flag |

**Implementation Filtering (Two-Stage):**

| Variable | Description |
|----------|-------------|
| `IMPL_SELECT` | Select implementations (empty = select all) |
| `IMPL_IGNORE` | Ignore implementations (empty = ignore none) |

**Component Filtering (Two-Stage):**

| Variable | Description |
|----------|-------------|
| `TRANSPORT_SELECT` | Select transports (empty = select all) |
| `TRANSPORT_IGNORE` | Ignore transports (empty = ignore none) |
| `SECURE_SELECT` | Select secure channels (empty = select all) |
| `SECURE_IGNORE` | Ignore secure channels (empty = ignore none) |
| `MUXER_SELECT` | Select muxers (empty = select all) |
| `MUXER_IGNORE` | Ignore muxers (empty = ignore none) |

**Test Name Filtering:**

| Variable | Description |
|----------|-------------|
| `TEST_SELECT` | Select tests by name pattern (empty = select all test names) |
| `TEST_IGNORE` | Ignore tests by name pattern (empty = ignore no test names) |

### Test-Type-Specific Variables

#### Transport Tests

No additional variables beyond common variables.

#### Perf Tests

**Perf-Specific Filtering:**

| Variable | Description |
|----------|-------------|
| `BASELINE_SELECT` | Select baseline tests (empty = select all) |
| `BASELINE_IGNORE` | Ignore baseline tests (empty = ignore none) |

**Perf-Specific Settings:**

| Variable | Description |
|----------|-------------|
| `ITERATIONS` | Number of iterations per test (default: 10) |
| `UPLOAD_BYTES` | Bytes to upload per test (default: 1073741824 = 1GB) |
| `DOWNLOAD_BYTES` | Bytes to download per test (default: 1073741824 = 1GB) |
| `DURATION` | Duration per iteration for throughput tests (seconds) |
| `LATENCY_ITERATIONS` | Number of iterations for latency tests (default: 100) |

#### Hole-Punch Tests

**Hole-Punch-Specific Filtering:**

| Variable | Description |
|----------|-------------|
| `RELAY_SELECT` | Select relay implementations (empty = select all) |
| `RELAY_IGNORE` | Ignore relay implementations (empty = ignore none) |
| `ROUTER_SELECT` | Select router implementations (empty = select all) |
| `ROUTER_IGNORE` | Ignore router implementations (empty = ignore none) |

## Filtering Model

### Two-Stage Filtering

All test suites use a two-stage filtering model with SELECT and IGNORE filters:

**Stage 1: SELECT filters** (Positive Filtering)
- **Purpose**: Narrow from the complete list of available items
- **Default**: Empty SELECT = select all items
- **Usage**: `--impl-select "~rust"` selects only rust implementations

**Stage 2: IGNORE filters** (Negative Filtering)
- **Purpose**: Remove unwanted items from the selected set
- **Default**: Empty IGNORE = ignore none
- **Usage**: `--impl-ignore "experimental"` removes experimental implementations

**Stage 3: TEST filters** (Test Name Filtering)
- **Purpose**: Filter by complete test name/ID patterns
- **Applied**: During test generation (inline)
- **Usage**: `--test-select "rust-v0.56 x"` matches test names

### Filter Patterns

Filters support sophisticated pattern matching:

- **Literal match**: `"rust-v0.56"` matches exactly
- **Pipe-separated OR**: `"rust-v0.56|go-v0.45"` matches either
- **Alias expansion**: `"~rust"` expands to all rust versions (from images.yaml)
- **Negation**: `"!~rust"` matches everything EXCEPT rust
- **Substring match**: `"experimental"` matches any ID containing this substring

### Filter Processing Order

1. **Expand aliases**: Resolve `~rust` to actual version list
2. **Apply SELECT**: Narrow scope from all items
3. **Apply IGNORE**: Remove unwanted items from selected set
4. **Apply TEST filters**: Match against complete test IDs (during generation)

### Examples

**Run only rust implementations:**
```bash
--impl-select "~rust"
```

**Run rust and go, but not experimental:**
```bash
--impl-select "~rust|~go" --impl-ignore "experimental"
```

**Run everything except QUIC transport:**
```bash
--transport-ignore "quic-v1"
```

**Complex filtering:**
```bash
--impl-select "~rust" \
--transport-select "tcp|quic-v1" \
--secure-select "noise" \
--impl-ignore "experimental" \
--test-ignore "cross-version"
```

## Example

```yaml
# Generated inputs.yaml for a "perf" test run
# This file captures all configuration for reproducibility
# Created: 2026-01-02T03:04:06Z

testType: perf

commandLineArgs:
  - "--impl-select"
  - "~rust"
  - "--impl-ignore"
  - "experimental"
  - "--baseline-select"
  - "iperf"
  - "--transport-ignore"
  - "quic-v1"
  - "--secure-select"
  - "noise"
  - "--test-ignore"
  - "experimental"
  - "--force-matrix-rebuild"
  - "--yes"

environmentVariables:
  IMAGES_YAML: "./images.yaml"
  CACHE_DIR: "/srv/cache"
  TEST_RUN_DIR: "/srv/cache/test-run"
  SCRIPT_DIR: "/srv/test-plans/perf/lib"
  SCRIPT_LIB_DIR: "/srv/test-plans/perf/lib/../../lib"
  DEBUG: "false"
  WORKER_COUNT: "1"

  # Implementation filtering
  IMPL_SELECT: "~rust"
  IMPL_IGNORE: "experimental"

  # Component filtering
  TRANSPORT_SELECT: ""
  TRANSPORT_IGNORE: "quic-v1"
  SECURE_SELECT: "noise"
  SECURE_IGNORE: ""
  MUXER_SELECT: ""
  MUXER_IGNORE: ""

  # Test name filtering
  TEST_SELECT: ""
  TEST_IGNORE: "experimental"

  # Perf-specific filtering
  BASELINE_SELECT: "iperf"
  BASELINE_IGNORE: ""

  # Other settings
  FORCE_MATRIX_REBUILD: "true"
  FORCE_IMAGE_REBUILD: "false"

  # Perf-specific settings
  ITERATIONS: "10"
  UPLOAD_BYTES: "1073741824"
  DOWNLOAD_BYTES: "1073741824"
  DURATION: ""
  LATENCY_ITERATIONS: "100"
```

## Generation

### When Generated

The `inputs.yaml` file is automatically generated at the start of each test run, after:
1. Command-line arguments are parsed
2. Environment variables are set
3. Test pass directory is created

### Generation Code

The file is generated by the `generate_inputs_yaml()` function in `lib/lib-inputs-yaml.sh`:

```bash
generate_inputs_yaml "$TEST_PASS_DIR/inputs.yaml" "$TEST_TYPE" "${ORIGINAL_ARGS[@]}"
```

**Implementation Details:**
- **Source**: `lib/lib-inputs-yaml.sh:17-81`
- **Called from**: `perf/run.sh:389` (and similar locations in other test suites)
- **Parameters**:
  1. Output file path (where to write the file)
  2. Test type (`transport`, `perf`, or `hole-punch`)
  3. Original command-line arguments (captured before parsing)

### Generation Process

1. **Capture Original Args**: Before argument parsing, the script saves `ORIGINAL_ARGS=("$@")` (see `perf/run.sh:24`)
2. **Parse Arguments**: The test runner parses all arguments and sets environment variables
3. **Create Test Pass Dir**: A unique test pass directory is created with format `<type>-<key>-<timestamp>`
4. **Generate File**: The `generate_inputs_yaml()` function writes all configuration to `$TEST_PASS_DIR/inputs.yaml`

## Loading

### Purpose

When an `inputs.yaml` file exists in the current directory, the test runner can load it to reproduce a previous test run.

### Loading Code

The file is loaded by inline functions at the top of each test runner (e.g., `perf/run.sh:30-65`):

```bash
load_inputs_yaml_inline() {
  local inputs_file="${1:-inputs.yaml}"
  # Loads and exports environment variables from inputs.yaml using yq
  # Source: perf/run.sh:30-48
}

get_yaml_args_inline() {
  local inputs_file="${1:-inputs.yaml}"
  # Extracts command-line arguments array from inputs.yaml
  # Source: perf/run.sh:51-57
}
```

### Loading Process

1. **Bootstrap Phase**: Before any libraries are loaded, check if `inputs.yaml` exists in current directory (perf/run.sh:60-65)
2. **Load Variables**: Extract and export all environment variables from `.environmentVariables` using `yq` (perf/run.sh:41-45)
3. **Load Arguments**: Extract command-line arguments array from `.commandLineArgs[]` using `yq` (perf/run.sh:56)
4. **Merge with CLI**: Append any new command-line arguments - CLI args take precedence and override inputs.yaml (perf/run.sh:68)
5. **Continue Execution**: Proceed with test execution using merged configuration

### Usage Example

```bash
# Copy inputs.yaml from a previous test run
cp /srv/cache/test-run/perf-abc123/inputs.yaml ./

# Re-run tests with exact same configuration
cd perf
./run.sh

# Or override specific parameters
./run.sh --iterations 20
```

## Snapshot Modification

When creating a test pass snapshot (using `--snapshot`), the `inputs.yaml` file is modified to work in the snapshot context.

### Modifications

The `modify_inputs_for_snapshot()` function (in `lib/lib-inputs-yaml.sh:87-111`) adjusts paths:

| Original Variable | Snapshot Value | Reason |
|------------------|----------------|--------|
| `IMAGES_YAML` | `./images.yaml` | Images config is copied to snapshot root |
| `CACHE_DIR` | `./` | Cache artifacts are packaged in snapshot root |
| `TEST_RUN_DIR` | `./re-run` | Test re-runs go to local directory |
| `SCRIPT_DIR` | `./lib` | Test-specific scripts are packaged in snapshot |
| `SCRIPT_LIB_DIR` | `./lib` | Shared libraries are packaged in snapshot |
| `--snapshot` flag | Removed from commandLineArgs | Prevents recursive snapshot creation |

Implementation uses `yq eval -i` to modify the YAML in-place:
```bash
yq eval -i '.environmentVariables.IMAGES_YAML = "./images.yaml"' "$inputs_file"
yq eval -i '.environmentVariables.CACHE_DIR = "./"' "$inputs_file"
yq eval -i '.environmentVariables.TEST_RUN_DIR = "./re-run"' "$inputs_file"
yq eval -i '.environmentVariables.SCRIPT_DIR = "./lib"' "$inputs_file"
yq eval -i '.environmentVariables.SCRIPT_LIB_DIR = "./lib"' "$inputs_file"
yq eval -i 'del(.commandLineArgs[] | select(. == "--snapshot"))' "$inputs_file"
```

### Snapshot Usage

```bash
# Extract a snapshot
unzip test-pass-snapshot.zip
cd test-pass-snapshot

# Run with snapshot's inputs.yaml
./run.sh
```

The modified `inputs.yaml` ensures the test runner uses snapshot-local resources instead of system-wide paths.

## Use Cases

### 1. Reproducing Test Failures

```bash
# A test run failed
# Copy its inputs.yaml
cp /srv/cache/test-run/perf-failed-run/inputs.yaml ./inputs.yaml

# Re-run with exact same configuration
cd perf && ./run.sh
```

### 2. Debugging with Debug Mode

```bash
# Manually edit inputs.yaml
yq eval -i '.environmentVariables.DEBUG = "true"' inputs.yaml

# Re-run with debug enabled
./run.sh
```

### 3. Cross-Environment Testing

```bash
# Generate inputs.yaml on one machine
./run.sh --test-select "rust-v0.56" --snapshot

# Copy snapshot to another machine
# Extract and run
unzip snapshot.zip
cd snapshot && ./run.sh
```

### 4. Audit Trail

```bash
# Review what configuration was used for a specific test run
cat /srv/cache/test-run/perf-abc123/inputs.yaml

# See exact command that was run
yq eval '.commandLineArgs[]' /srv/cache/test-run/perf-abc123/inputs.yaml
```

## Related Files

- **Generation**: `lib/lib-inputs-yaml.sh` - Functions to generate and modify inputs.yaml
  - `generate_inputs_yaml()` function at lines 17-81
  - `modify_inputs_for_snapshot()` function at lines 87-111
  - Test-type-specific variables added at lines 56-78
- **Loading**: Inline functions in each test runner's bootstrap section
  - `perf/run.sh:30-71` - Bootstrap logic with inline load functions
  - `transport/run.sh:30-71` - Bootstrap logic with inline load functions
  - `hole-punch/run.sh:30-71` - Bootstrap logic with inline load functions
- **Usage**:
  - `perf/run.sh:363` - Calls `generate_inputs_yaml()`
  - `transport/run.sh:~363` - Calls `generate_inputs_yaml()`
  - `hole-punch/run.sh:363` - Calls `generate_inputs_yaml()`
- **Snapshot Creation**: `lib/lib-snapshot-creation.sh` - Creates snapshots and modifies inputs.yaml

## Complete Example: Hole-Punch Tests

```yaml
# Generated inputs.yaml for a "hole-punch" test run
# This file captures all configuration for reproducibility
# Created: 2026-01-14T03:04:06Z

testType: hole-punch

commandLineArgs:
  - "--test-ignore"
  - "!rust-v0.56"
  - "--relay-ignore"
  - "!rust-v0.56"
  - "--router-ignore"
  - "!linux"
  - "--transport-ignore"
  - "webrtc-direct"

environmentVariables:
  IMAGES_YAML: "./images.yaml"
  CACHE_DIR: "/srv/cache"
  TEST_RUN_DIR: "/srv/cache/test-run"
  SCRIPT_DIR: "/srv/test-plans/hole-punch/lib"
  SCRIPT_LIB_DIR: "/srv/test-plans/lib"
  DEBUG: "false"
  WORKER_COUNT: "8"
  TEST_IGNORE: "!rust-v0.56"
  TRANSPORT_IGNORE: "webrtc-direct"
  SECURE_IGNORE: ""
  MUXER_IGNORE: ""
  FORCE_MATRIX_REBUILD: "false"
  FORCE_IMAGE_REBUILD: "false"
  RELAY_IGNORE: "!rust-v0.56"
  ROUTER_IGNORE: "!linux"
```

## Complete Example: Transport Tests

```yaml
# Generated inputs.yaml for a "transport" test run
# This file captures all configuration for reproducibility
# Created: 2026-01-14T03:04:06Z

testType: transport

commandLineArgs:
  - "--test-ignore"
  - "!~rust"
  - "--workers"
  - "8"

environmentVariables:
  IMAGES_YAML: "./images.yaml"
  CACHE_DIR: "/srv/cache"
  TEST_RUN_DIR: "/srv/cache/test-run"
  SCRIPT_DIR: "/srv/test-plans/transport/lib"
  SCRIPT_LIB_DIR: "/srv/test-plans/lib"
  DEBUG: "false"
  WORKER_COUNT: "8"
  TEST_IGNORE: "!~rust"
  TRANSPORT_IGNORE: ""
  SECURE_IGNORE: ""
  MUXER_IGNORE: ""
  FORCE_MATRIX_REBUILD: "false"
  FORCE_IMAGE_REBUILD: "false"
```
