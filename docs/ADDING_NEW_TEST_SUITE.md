# Adding a New Test Suite to the Unified Build System

Guide for adding new test suites (e.g., "relay-performance", "e2e-tests") that use the unified YAML-based Docker build system.

---

## Overview

The unified build system makes it easy to add new test suites. You only need to create a thin orchestrator script that generates YAML files and calls the shared executor.

**Shared Infrastructure (Already Exists):**
- `lib/build-single-image.sh` - YAML-based executor
- `lib/lib-image-building.sh` - Build functions
- `lib/lib-remote-execution.sh` - Remote build support

**What You Create:**
- `<new-test>/lib/build-images.sh` - Orchestrator (80-150 lines)
- `<new-test>/impls.yaml` - Implementation definitions

---

## Step-by-Step Guide

### Step 1: Create Test Suite Directory

```bash
mkdir -p my-new-test/scripts
mkdir -p my-new-test/impls
cd my-new-test
```

### Step 2: Create impls.yaml

Define your implementations:

```yaml
# my-new-test/impls.yaml

implementations:
  - id: rust-v0.56
    source:
      type: local
      path: impls/rust/v0.56
      dockerfile: Dockerfile
    # ... other fields

  - id: go-v0.45
    source:
      type: github
      repo: libp2p/go-libp2p
      commit: abc123def456
      dockerfile: interop/Dockerfile
      buildContext: .
    # ... other fields

  - id: chromium-js-v3.x
    source:
      type: browser
      baseImage: js-v3.x
      browser: chromium
      dockerfile: impls/js/v3.x/BrowserDockerfile
    # ... other fields
```

### Step 3: Create build-images.sh Orchestrator

```bash
#!/bin/bash
# my-new-test/lib/build-images.sh

set -euo pipefail

# Get script directory and change to test directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Configuration
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
FILTER="${1:-}"           # Optional filter
FORCE_REBUILD="${2:-false}"
IMAGE_PREFIX="my-new-test-"
BUILD_SCRIPT="$SCRIPT_DIR/../../lib/build-single-image.sh"

echo "  → Cache directory: $CACHE_DIR"
[ -n "$FILTER" ] && echo "  → Filter: $FILTER"
echo ""

# Ensure cache directories exist
mkdir -p "$CACHE_DIR/snapshots"
mkdir -p "$CACHE_DIR/build-yamls"

# Loop through implementations
impl_count=$(yq eval '.implementations | length' impls.yaml)

for ((i=0; i<impl_count; i++)); do
    impl_id=$(yq eval ".implementations[$i].id" impls.yaml)

    # Apply filter if specified
    if [ -n "$FILTER" ]; then
        match_found=false
        IFS='|' read -ra FILTER_PATTERNS <<< "$FILTER"
        for pattern in "${FILTER_PATTERNS[@]}"; do
            if [[ "$impl_id" == *"$pattern"* ]]; then
                match_found=true
                break
            fi
        done
        [ "$match_found" = false ] && continue
    fi

    image_name="${IMAGE_PREFIX}${impl_id}"
    source_type=$(yq eval ".implementations[$i].source.type" impls.yaml)

    # Check if already built
    if [ "$FORCE_REBUILD" = "false" ] && docker image inspect "$image_name" &>/dev/null; then
        echo "  ✓ $image_name (already built)"
        continue
    fi

    # Create YAML file
    yaml_file="$CACHE_DIR/build-yamls/docker-build-my-new-test-${impl_id}.yaml"

    cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: peer
imagePrefix: $IMAGE_PREFIX
sourceType: $source_type
buildLocation: local
cacheDir: $CACHE_DIR
forceRebuild: $FORCE_REBUILD
outputStyle: clean
EOF

    # Add source-specific parameters
    case "$source_type" in
        github)
            repo=$(yq eval ".implementations[$i].source.repo" impls.yaml)
            commit=$(yq eval ".implementations[$i].source.commit" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(yq eval ".implementations[$i].source.buildContext // \".\"" impls.yaml)

            cat >> "$yaml_file" <<EOF

github:
  repo: $repo
  commit: $commit
  dockerfile: $dockerfile
  buildContext: $build_context
EOF
            ;;

        local)
            local_path=$(yq eval ".implementations[$i].source.path" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile // \"Dockerfile\"" impls.yaml)

            cat >> "$yaml_file" <<EOF

local:
  path: $local_path
  dockerfile: $dockerfile
EOF
            ;;

        browser)
            base_image=$(yq eval ".implementations[$i].source.baseImage" impls.yaml)
            browser=$(yq eval ".implementations[$i].source.browser" impls.yaml)
            dockerfile=$(yq eval ".implementations[$i].source.dockerfile" impls.yaml)
            build_context=$(dirname "$dockerfile")

            cat >> "$yaml_file" <<EOF

browser:
  baseImage: $base_image
  browser: $browser
  dockerfile: $dockerfile
  buildContext: $build_context
EOF
            ;;
    esac

    # Execute build
    bash "$BUILD_SCRIPT" "$yaml_file" || exit 1
done

echo ""
echo "✓ All required images built successfully"
```

**That's it!** 80-100 lines for a complete build system.

---

## Adding Remote Build Support

If your test suite needs remote builds (like perf tests):

### Step 1: Add Server Config to impls.yaml

```yaml
implementations:
  - id: rust-v0.56
    server: my-server-1  # NEW: Server identifier
    source:
      type: local
      path: impls/rust/v0.56
      dockerfile: Dockerfile

servers:  # NEW: Server definitions
  - id: my-server-1
    hostname: server1.example.com
    username: testuser
```

### Step 2: Create Server Helper Functions

```bash
# my-new-test/lib/lib-my-test.sh

get_server_config() {
    local impl_id="$1"
    yq eval ".implementations[] | select(.id == \"$impl_id\") | .server // \"local\"" impls.yaml
}

get_remote_hostname() {
    local server_id="$1"
    yq eval ".servers[] | select(.id == \"$server_id\") | .hostname" impls.yaml
}

get_remote_username() {
    local server_id="$1"
    yq eval ".servers[] | select(.id == \"$server_id\") | .username" impls.yaml
}

is_remote_server() {
    local server_id="$1"
    [ "$server_id" != "local" ] && [ -n "$server_id" ]
}
```

### Step 3: Update build-images.sh

```bash
# Source remote execution library
source "../lib/lib-remote-execution.sh"
source "lib/lib-my-test.sh"

# In the loop:
server_id=$(get_server_config "$impl_id")

if is_remote_server "$server_id"; then
    build_location="remote"
    hostname=$(get_remote_hostname "$server_id")
    username=$(get_remote_username "$server_id")

    # Add to YAML
    cat >> "$yaml_file" <<EOF

remote:
  server: $server_id
  hostname: $hostname
  username: $username
EOF

    # Execute remote build
    build_on_remote "$yaml_file" "$username" "$hostname" "$BUILD_SCRIPT"
else
    # Execute local build
    bash "$BUILD_SCRIPT" "$yaml_file"
fi
```

---

## Adding Custom Image Types

If you have special components (like hole-punch has relays/routers):

```bash
build_image_type() {
    local image_type="$1"        # custom, special, etc.
    local yaml_section="$2"      # customComponents
    local filter="$3"
    local prefix="my-new-test-${image_type}-"

    local count=$(yq eval ".$yaml_section | length" impls.yaml)

    for ((i=0; i<count; i++)); do
        # Same logic as peers, just different prefix!
    done
}

# Build custom types
build_image_type "custom" "customComponents" "$CUSTOM_FILTER"
build_image_type "peer" "implementations" "$IMPL_FILTER"
```

---

## Testing Your New Test Suite

### 1. Test Build Script
```bash
cd my-new-test
bash lib/build-images.sh "rust-v0.56" "false"
```

### 2. Test with run_tests.sh
```bash
./run_tests.sh --list-impls
./run_tests.sh --test-select "rust-v0.56" --list-tests
```

### 3. Add to Integration Tests
```bash
# In tests/test-unified-build-system.sh
cd "$TEST_DIR/my-new-test"
run_test "My new test orchestrator" \
    "bash lib/build-images.sh 'rust-v0.56' 'false'" \
    0
```

---

## Best Practices

### ✅ DO:
- Use transport's `outputStyle: clean` for best UX
- Store YAML files in `/srv/cache/build-yamls/`
- Use descriptive image prefixes (`my-test-`, not just `test-`)
- Test all three source types (github/local/browser)
- Include filter support in orchestrator
- Preserve transport aesthetic in output

### ❌ DON'T:
- Modify shared scripts (`build-single-image.sh`, `lib-*.sh`)
- Hardcode paths (use CACHE_DIR variable)
- Skip error handling
- Use custom docker output formatting (use outputStyle instead)
- Duplicate code from other test suites

---

## Example: Complete New Test Suite

```
my-new-test/
├── impls.yaml                       # Implementation definitions
├── lib/
│   ├── build-images.sh             # Orchestrator (80-100 lines)
│   ├── generate-tests.sh           # Test matrix generator
│   └── run-single-test.sh          # Single test runner
└── run_tests.sh                    # Main test runner

Uses (shared):
├── lib/build-single-image.sh   # Executor
├── lib/lib-image-building.sh   # Build functions
└── lib/lib-remote-execution.sh # Remote builds
```

**Time to implement:** 1-2 hours (mostly copy-paste from existing tests)

---

## Checklist for New Test Suite

- [ ] Created `<test>/impls.yaml` with implementations
- [ ] Created `<test>/lib/build-images.sh` orchestrator
- [ ] Tested local builds
- [ ] Tested remote builds (if needed)
- [ ] Tested all source types (github/local/browser)
- [ ] Added integration test
- [ ] Updated main README
- [ ] Documented test-specific features

---

## Need Help?

See existing test suites as examples:
- **Simplest:** `transport/lib/build-images.sh` (138 lines)
- **With remote:** `perf/lib/build-images.sh` (171 lines)
- **Multi-component:** `hole-punch/lib/build-images.sh` (148 lines)

All use the same unified system! 🎉
