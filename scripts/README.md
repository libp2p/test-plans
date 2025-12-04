# Common Test Scripts Library

This directory contains shared scripts and libraries used by both `hole-punch` and `transport` test suites.

## Overview

The refactoring extracted ~1,500 lines of duplicate code into reusable libraries, reducing test-specific code by:
- **Hole-punch scripts**: 44% reduction (2,612 → 1,469 lines)
- **Transport scripts**: 57% reduction (2,209 → 947 lines)

## Directory Structure

```
scripts/
├── README.md                      # This file
├── check-dependencies.sh          # Unified dependency checker
├── lib-test-aliases.sh            # Test alias expansion functions
├── lib-test-filtering.sh          # Test filtering functions
├── lib-test-caching.sh            # Test matrix caching functions
└── (future additions)
    ├── lib-image-builder.sh       # Image building functions
    ├── lib-test-runner.sh         # Test execution functions
    ├── lib-dashboard.sh           # Dashboard generation functions
    └── create-snapshot.sh         # Snapshot creation script
```

## Common Scripts

### check-dependencies.sh

**Purpose**: Checks for required system dependencies across all test types.

**Features**:
- Verifies bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip
- Auto-detects `docker compose` vs `docker-compose` command
- Exports `DOCKER_COMPOSE_CMD` to `/tmp/docker-compose-cmd.txt`

**Usage**:
```bash
# From test-specific directory
bash ../scripts/check-dependencies.sh
```

**Exit Codes**:
- `0`: All dependencies satisfied
- `1`: Missing or outdated dependencies

---

## Common Libraries

### lib-test-aliases.sh

**Purpose**: Provides test alias expansion for simplified test selection.

**Functions**:

#### `load_aliases()`
Loads test aliases from `impls.yaml` into a global `ALIASES` associative array.

```yaml
# Example impls.yaml
test-aliases:
  - alias: "rust"
    value: "rust-v0.56|rust-v0.55"
```

#### `expand_aliases(input)`
Expands alias syntax in test selection strings.

**Supported syntax**:
- `~alias` - Expands to alias value
- `!~alias` - Expands to all implementations NOT matching alias

**Example**:
```bash
source lib-test-aliases.sh
load_aliases
expanded=$(expand_aliases "~rust")
# Result: "rust-v0.56|rust-v0.55"
```

#### `get_all_impl_ids()`
Returns all implementation IDs as a pipe-separated string.

---

### lib-test-filtering.sh

**Purpose**: Provides test filtering logic for test matrix generation.

**Functions**:

#### `impl_matches_select(impl_id)`
Checks if an implementation ID matches any SELECT pattern.

**Parameters**:
- `impl_id`: Implementation ID to check
- Uses global `SELECT_PATTERNS` array

**Returns**:
- `0` (true): Matches select criteria
- `1` (false): Does not match

#### `matches_select(test_name)`
Checks if a test name matches any SELECT pattern.

**Parameters**:
- `test_name`: Full test name

**Returns**:
- `0` (true): Test should be included
- `1` (false): Test should be excluded

#### `should_ignore(test_name)`
Checks if a test name matches any IGNORE pattern.

**Parameters**:
- `test_name`: Full test name

**Returns**:
- `0` (true): Test should be ignored
- `1` (false): Test should not be ignored

#### `get_common(list1, list2)`
Finds common elements between two space-separated lists.

**Example**:
```bash
common=$(get_common "tcp ws quic" "ws quic webrtc")
# Result: "ws quic"
```

---

### lib-test-caching.sh

**Purpose**: Manages test matrix caching to speed up repeated test runs.

**Functions**:

#### `compute_cache_key(test_select, test_ignore, debug)`
Computes a cache key based on test configuration.

**Parameters**:
- `test_select`: TEST_SELECT filter string
- `test_ignore`: TEST_IGNORE filter string
- `debug`: Debug mode flag

**Returns**: SHA256 hash of impls.yaml + parameters

**Example**:
```bash
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "false")
# Result: "6b10a3ee..."
```

#### `check_and_load_cache(cache_key, cache_dir, output_dir)`
Checks for cached test matrix and loads it if found.

**Parameters**:
- `cache_key`: Cache key from `compute_cache_key()`
- `cache_dir`: Cache directory path (e.g., `/srv/cache`)
- `output_dir`: Output directory for test-matrix.yaml

**Returns**:
- `0`: Cache hit, matrix loaded
- `1`: Cache miss, needs generation

#### `save_to_cache(output_dir, cache_key, cache_dir)`
Saves generated test matrix to cache.

**Parameters**:
- `output_dir`: Directory containing test-matrix.yaml
- `cache_key`: Cache key
- `cache_dir`: Cache directory path

---

## Usage Patterns

### Pattern 1: Using Common Standalone Scripts

Test-specific scripts call common scripts directly:

```bash
# hole-punch/run_tests.sh
bash ../scripts/check-dependencies.sh
```

### Pattern 2: Using Common Function Libraries

Test-specific scripts source libraries and call functions:

```bash
# hole-punch/scripts/generate-tests.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib-test-aliases.sh"
source "$SCRIPT_DIR/../../scripts/lib-test-filtering.sh"
source "$SCRIPT_DIR/../../scripts/lib-test-caching.sh"

# Use the functions
load_aliases
TEST_SELECT=$(expand_aliases "$TEST_SELECT")
if matches_select "$test_name"; then
    # Add test
fi
```

### Pattern 3: Cache-Aware Test Generation

```bash
# Compute cache key
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG")

# Try to load from cache
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$OUTPUT_DIR"; then
    exit 0  # Cache hit, done!
fi

# Cache miss - generate tests
# ... test generation logic ...

# Save to cache
save_to_cache "$OUTPUT_DIR" "$cache_key" "$CACHE_DIR"
```

---

## Test-Specific Customizations

### Hole-Punch Tests

**Test Dimensions**: 8D permutations
- dialer × listener × transport × secureChannel × muxer × relay × dialer_router × listener_router

**Standalone Transports** (no secure/muxer): quic, quic-v1, webtransport, webrtc, webrtc-direct

**Example Test Names**:
```
linux x linux (tcp, noise, yamux) [linux] - [linux] - [linux]
linux x linux (quic-v1) [linux] - [linux] - [linux]
```

### Transport Tests

**Test Dimensions**: 5D permutations
- dialer × listener × transport × secureChannel × muxer

**Standalone Transports** (no secure/muxer): quic, quic-v1, webtransport, webrtc, webrtc-direct

**Example Test Names**:
```
rust-v0.56 x rust-v0.56 (tcp, noise, yamux)
rust-v0.56 x rust-v0.56 (quic-v1)
```

---

## Adding New Test Types

To create a new test type using these common libraries:

1. **Create test directory** (e.g., `new-test-type/`)

2. **Create impls.yaml** with:
   ```yaml
   implementations:
     - id: my-impl
       transports: [tcp, quic-v1]
       secureChannels: [noise, tls]
       muxers: [yamux, mplex]
       source: { ... }
   ```

3. **Create generate-tests.sh** that sources common libraries:
   ```bash
   source "../scripts/lib-test-aliases.sh"
   source "../scripts/lib-test-filtering.sh"
   source "../scripts/lib-test-caching.sh"

   load_aliases
   # ... custom test generation logic ...
   ```

4. **Create run_tests.sh** that uses check-dependencies.sh:
   ```bash
   bash ../scripts/check-dependencies.sh
   ```

---

## Maintenance Guidelines

### When to Update Common Libraries

**Update common libraries when**:
- Bug fixes affect multiple test types
- New filtering features needed globally
- Performance improvements applicable to all

**Keep test-specific when**:
- Logic unique to one test type
- Different network topologies
- Type-specific test execution

### Version Compatibility

Common libraries maintain backward compatibility. Breaking changes require:
1. Update all test-specific scripts
2. Document in this README
3. Test both hole-punch and transport suites

---

## Testing

After modifying common libraries, test both suites:

```bash
# Test hole-punch generation
cd hole-punch
TEST_PASS_DIR=/tmp/hp-test bash scripts/generate-tests.sh

# Test transport generation
cd transport
TEST_PASS_DIR=/tmp/ti-test bash scripts/generate-tests.sh "rust-v0.56"
```

---

## Performance Notes

### Caching

Test matrix caching provides ~10-100x speedup for repeated test runs with same configuration:
- **Cache miss**: ~2-5 seconds (generation)
- **Cache hit**: ~50-200ms (load from file)

### Memory Usage

Libraries use associative arrays for O(1) lookups:
- 100 implementations: ~1MB memory
- 1000 implementations: ~10MB memory

---

## Troubleshooting

### "Command not found" errors

Ensure scripts are executable:
```bash
chmod +x scripts/*.sh
```

### "ALIASES: unbound variable"

Ensure `load_aliases()` is called before using alias functions:
```bash
load_aliases  # Must be called first
expand_aliases "$TEST_SELECT"  # Now safe to use
```

### Cache not working

Check cache directory permissions:
```bash
mkdir -p /srv/cache/test-matrix
chmod -R 755 /srv/cache
```

---

## Future Enhancements

Planned additions:
- `lib-image-builder.sh` - Common Docker image building
- `lib-test-runner.sh` - Shared test execution functions
- `lib-dashboard.sh` - Common dashboard generation
- `create-snapshot.sh` - Unified snapshot creation

---

**Last Updated**: 2025-12-03
**Version**: 1.0.0
