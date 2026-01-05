# Unified Docker Image Build System

YAML-based Docker image build system for the perf test suite.

This documentation reflects the actual implementation in `lib/build-single-image.sh`, `lib/lib-image-building.sh`, and how it's used in `perf/run.sh`.

---

## Overview

The build system provides:
- **Automatic image building** from `images.yaml` definitions
- **Multiple source types** (local, GitHub, browser)
- **Build caching** to avoid rebuilding existing images
- **GitHub snapshot caching** for faster rebuilds
- **Consistent YAML-based interface** for all builds

---

## Quick Start

### Build Images During Test Run (Automatic)

Images are built automatically when running perf tests:

```bash
cd perf
./run.sh --test-ignore "experimental"
```

The test runner automatically:
1. Reads `images.yaml` to determine required images
2. Checks which images need building
3. Generates build YAML files
4. Executes builds via `lib/build-single-image.sh`

### Build a Single Image Manually

```bash
# 1. Create YAML file
cat > /tmp/my-build.yaml <<EOF
imageName: test-rust-v0.56
imageType: peer
imagePrefix: test
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
EOF

# 2. Build
./lib/build-single-image.sh /tmp/my-build.yaml
```

### Force Rebuild All Images

```bash
cd perf
./run.sh --force-image-rebuild --test-ignore "experimental"
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│              perf/run.sh (841 lines)                     │
│         Main test runner and orchestrator                │
└───────────────────────────┬──────────────────────────────┘
                            │
                            │ Calls build_images_from_section()
                            │ (lines 554-555)
                            │
┌───────────────────────────▼──────────────────────────────┐
│       lib/lib-image-building.sh (491 lines)              │
│         build_images_from_section() function             │
│              (lines 14-157)                              │
│                                                          │
│  • Reads images.yaml                                    │
│  • Applies filters                                      │
│  • Generates YAML files for each image                 │
│  • Calls build-single-image.sh                         │
└───────────────────────────┬──────────────────────────────┘
                            │
                            │ For each image
                            │
┌───────────────────────────▼──────────────────────────────┐
│       lib/build-single-image.sh (108 lines)              │
│              YAML Executor                               │
│                                                          │
│  • Loads YAML parameters                               │
│  • Validates inputs                                    │
│  • Delegates to build functions                        │
│  • Shows result with image ID                          │
└───────────────────────────┬──────────────────────────────┘
                            │
                            │ Calls build_from_*()
                            │
┌───────────────────────────▼──────────────────────────────┐
│       lib/lib-image-building.sh (491 lines)              │
│            Build Implementation Functions                │
│                                                          │
│  • build_from_local() (lines 393-425)                  │
│  • build_from_github() (lines 287-338)                 │
│  • build_from_github_with_submodules() (lines 341-390) │
│  • build_browser_image() (lines 428-473)               │
│  • download_github_snapshot() (lines 160-182)          │
│  • clone_github_repo_with_submodules() (lines 210-284) │
└─────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Test Runner Orchestrator (perf/run.sh)

**Location:** `perf/run.sh` (841 lines)

**Build Orchestration** (lines 535-561):
```bash
print_banner "Docker Image Builds"
indent

# Calculate required images
readarray -t required_baseline_ids < <(yq eval '.baselines[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u)
readarray -t required_impl_ids < <(yq eval '.tests[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u)

# Convert to pipe-separated filter
IMAGE_FILTER=$(printf '%s\n' "${required_baseline_ids[@]}" "${required_impl_ids[@]}" | sort -u | paste -sd'|')

print_message "Building required images: ${IMAGE_FILTER}"

# Build images
export TEST_TYPE="perf"
export IMAGES_YAML
export FORCE_IMAGE_REBUILD
build_images_from_section "baselines" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

unindent
echo ""
```

**Purpose:**
- Determine which images are needed from test matrix
- Create filter string with required image IDs
- Call `build_images_from_section()` for baselines and implementations

### 2. Build Generator (lib/lib-image-building.sh)

**Function:** `build_images_from_section()` (lines 14-157)

**Signature:**
```bash
build_images_from_section() {
  local section="$1"      # "implementations" or "baselines"
  local filter="${2:-}"   # Optional: "rust-v0.56|go-v0.45"
  local force_image_rebuild="${3:-false}"
}
```

**Process:**
1. **Read images.yaml** to get implementation count
2. **Iterate each implementation**
3. **Apply filter** (if specified)
4. **Check if image exists** (skip if already built, unless force rebuild)
5. **Generate YAML file** at `$CACHE_DIR/build-yamls/docker-build-perf-<id>.yaml`
6. **Execute build** via `lib/build-single-image.sh`

**YAML Generation** (lines 63-138):
```bash
cat > "$yaml_file" <<EOF
imageName: $image_name
imageType: peer
imagePrefix: "${TEST_TYPE}"
sourceType: $source_type
buildLocation: $build_location
cacheDir: $CACHE_DIR
forceRebuild: $force_image_rebuild
outputStyle: clean
EOF

# Add source-specific parameters (github, local, or browser)
case "$source_type" in
  github)
    cat >> "$yaml_file" <<EOF
github:
  repo: $repo
  commit: $commit
  dockerfile: $dockerfile
  buildContext: $build_context
requiresSubmodules: $requires_submodules
EOF
    ;;
  local)
    cat >> "$yaml_file" <<EOF
local:
  path: $local_path
  dockerfile: $dockerfile
EOF
    ;;
  # ... browser case
esac
```

### 3. Build Executor (lib/build-single-image.sh)

**Location:** `lib/build-single-image.sh` (108 lines)

**Purpose:**
- Load YAML parameters using `yq`
- Validate required fields
- Check if image already exists (unless force rebuild)
- Delegate to appropriate build function
- Display result with image ID

**Execution Flow:**
```bash
# Load parameters
imageName=$(yq eval '.imageName' "$YAML_FILE")
sourceType=$(yq eval '.sourceType' "$YAML_FILE")
forceRebuild=$(yq eval '.forceRebuild' "$YAML_FILE")
cacheDir=$(yq eval '.cacheDir' "$YAML_FILE")
requiresSubmodules=$(yq eval '.requiresSubmodules // false' "$YAML_FILE")

# Check if already built
if [ "$forceRebuild" != "true" ]; then
  if docker image inspect "$imageName" &>/dev/null; then
    print_success "$imageName (already built)"
    exit 0
  fi
fi

# Build based on source type
case "$sourceType" in
  github)
    if [ "$requiresSubmodules" = "true" ]; then
      build_from_github_with_submodules "$YAML_FILE" "$OUTPUT_FILTER"
    else
      build_from_github "$YAML_FILE" "$OUTPUT_FILTER"
    fi
    ;;
  local)
    build_from_local "$YAML_FILE" "$OUTPUT_FILTER"
    ;;
  browser)
    build_browser_image "$YAML_FILE" "$OUTPUT_FILTER"
    ;;
esac
```

### 4. Build Functions (lib/lib-image-building.sh)

**Location:** `lib/lib-image-building.sh` (491 lines)

**Functions:**

#### Local Builds (lines 393-425)
```bash
build_from_local() {
  local yaml_file="$1"
  local output_filter="$2"

  local image_name=$(yq eval '.imageName' "$yaml_file")
  local local_path=$(yq eval '.local.path' "$yaml_file")
  local dockerfile=$(yq eval '.local.dockerfile' "$yaml_file")

  # Validate path
  if [ ! -d "$local_path" ]; then
    print_error "Local path not found: $local_path"
    return 1
  fi

  # Build
  docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"
}
```

**Currently used by all perf implementations.**

#### GitHub Builds - Snapshot Method (lines 287-338)
```bash
build_from_github() {
  # Download snapshot to cache
  local snapshot_file=$(download_github_snapshot "$repo" "$commit" "$cache_dir")

  # Extract to temp directory
  local work_dir=$(extract_github_snapshot "$snapshot_file" "$repo_name" "$commit")

  # Build
  docker build -f "$extracted_dir/$dockerfile" -t "$image_name" "$context_dir"

  # Cleanup
  rm -rf "$work_dir"
}
```

**Implemented but not currently used in perf.**

#### GitHub Builds - Clone with Submodules (lines 341-390)
```bash
build_from_github_with_submodules() {
  # Clone with submodules (cached)
  local work_dir=$(clone_github_repo_with_submodules "$repo" "$commit" "$cache_dir")

  # Build
  docker build -f "$cloned_dir/$dockerfile" -t "$image_name" "$context_dir"

  # Cleanup
  rm -rf "$work_dir"
}
```

**Implemented but not currently used in perf.**

#### Browser Builds (lines 428-473)
```bash
build_browser_image() {
  # Verify base image exists
  docker image inspect "$base_image_name" &>/dev/null

  # Tag base image
  docker tag "$base_image_name" "node-$base_image"

  # Build with browser arg
  docker build \
    --build-arg BASE_IMAGE="node-$base_image" \
    --build-arg BROWSER="$browser" \
    -t "$image_name" \
    "$build_context"
}
```

**Implemented but not used in perf.**

#### Caching Functions

**GitHub Snapshot Download** (lines 160-182):
```bash
download_github_snapshot() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local snapshot_file="$cache_dir/snapshots/$commit.zip"

  if [ ! -f "$snapshot_file" ]; then
    wget -q -O "$snapshot_file" "https://github.com/$repo/archive/$commit.zip"
  fi

  echo "$snapshot_file"
}
```

**Git Clone with Submodules** (lines 210-284):
```bash
clone_github_repo_with_submodules() {
  local repo="$1"
  local commit="$2"
  local cache_dir="$3"

  local cached_clone="$cache_dir/git-repos/${repo_name}-${commit}"

  # Check cache
  if [ -d "$cached_clone" ]; then
    # Copy from cache
    local work_dir=$(mktemp -d)
    cp -r "$cached_clone" "$work_dir/$repo_name"
    echo "$work_dir"
    return 0
  fi

  # Clone, checkout, and initialize submodules
  git clone --depth 1 "https://github.com/$repo.git" "$clone_dir"
  cd "$clone_dir"
  git fetch --depth 1 origin "$commit"
  git checkout "$commit"
  git submodule update --init --recursive --depth 1

  # Cache for future use
  cp -r "$clone_dir" "$cached_clone"

  echo "$work_dir"
}
```

---

## Supported Features

### Source Types

| Type | Status | Usage | Implementation |
|------|--------|-------|----------------|
| **local** | ✅ Implemented & Used | All perf implementations | lib/lib-image-building.sh:393-425 |
| **github** | ✅ Implemented | Not used in perf | lib/lib-image-building.sh:287-338 |
| **github + submodules** | ✅ Implemented | Not used in perf | lib/lib-image-building.sh:341-390 |
| **browser** | ✅ Implemented | Not used in perf | lib/lib-image-building.sh:428-473 |

### Build Locations

| Type | Status | Notes |
|------|--------|-------|
| **local** | ✅ Implemented & Used | All builds on current machine |
| **remote** | ❌ Not Implemented | Code commented out (lib/lib-image-building.sh:41-50) |

### Image Types

| Type | Status | Usage |
|------|--------|-------|
| **peer** | ✅ Used | All perf implementations and baselines |
| **relay** | ⚠️ Defined but unused | For hole-punch tests |
| **router** | ⚠️ Defined but unused | For hole-punch tests |

### Output Styles

| Style | Description | Implementation |
|-------|-------------|----------------|
| **clean** | Full Docker output (default) | `cat` |
| **indented** | 4-space indented output | `sed 's/^/    /'` |
| **filtered** | Only steps and errors | `grep -E '^(#\|Step\|Successfully\|ERROR)'` |

**Perf uses:** `clean` (outputStyle: clean in all generated YAMLs)

---

## Benefits

### 1. Code Reuse

**Shared Infrastructure:**
- `lib/build-single-image.sh` (108 lines) - Build executor
- `lib/lib-image-building.sh` (491 lines) - Build functions
- **Total:** 599 lines of reusable code

**Result:**
- Single implementation of build logic
- Consistent behavior across all use cases
- Fix bugs once, benefits everywhere

### 2. Automatic Image Management

**Image caching** (lib/build-single-image.sh:48-53):
```bash
if [ "$forceRebuild" != "true" ]; then
  if docker image inspect "$imageName" &>/dev/null; then
    print_success "$imageName (already built)"
    exit 0  # Skip build
  fi
fi
```

**Benefits:**
- Faster test runs (only build what's needed)
- Consistent with Docker's layer caching
- Can force rebuild with `--force-image-rebuild`

### 3. GitHub Caching

**Snapshot caching** prevents repeated downloads:

```
$CACHE_DIR/snapshots/
└── 70082df7e6181722630eabc5de5373733aac9a21.zip

$CACHE_DIR/git-repos/
└── rust-libp2p-70082df7/
    ├── Cargo.toml
    ├── interop-tests/
    └── ... (with submodules initialized)
```

**Benefits:**
- First build: Download snapshot from GitHub
- Subsequent builds: Use cached snapshot
- Submodules: Clone cached for future use

### 4. Consistent Output

All builds show clean, consistent output:

```
===============================================================================
Building: perf-rust-v0.56
===============================================================================
    Type: local
    Path: images/rust/v0.56
    Building Docker image...
    [Docker build output...]
    ✓ Built: perf-rust-v0.56
    ✓ Image ID: a3f7b21c1d4e...
```

### 5. Easy Debugging

**Inspect generated YAML:**
```bash
cat /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
```

**Rerun single build:**
```bash
./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
```

**Debug mode:**
```bash
bash -x ./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
```

---

## Cache Structure

```
/srv/cache/
├── snapshots/                    # GitHub snapshot zips
│   └── <commit-hash>.zip        # Cached GitHub archives
│
├── git-repos/                    # Git clones with submodules
│   └── <repo-name>-<commit>/    # Cached git repositories
│
├── build-yamls/                  # Generated build YAML files
│   └── docker-build-perf-<id>.yaml
│
├── test-run/                     # Test run artifacts
│   └── perf-<key>-HHMMSS-DD-MM-YYYY/
│
└── test-run-matrix/              # Cached test matrices
    └── perf-<key>.yaml
```

**Cache Benefits:**
- **Snapshots**: Download once, use many times
- **Git repos**: Clone with submodules once, reuse
- **Build YAMLs**: Inspect/debug build parameters
- **Test runs**: Full reproducibility

---

## Complete Example: Perf Build Flow

### Step 1: User runs perf tests

```bash
cd perf
./run.sh --test-ignore "experimental" --iterations 5
```

### Step 2: Test runner determines required images

From `perf/run.sh:539-543`:
```bash
readarray -t required_baseline_ids < <(yq eval '.baselines[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u)
readarray -t required_impl_ids < <(yq eval '.tests[].dialer.id' "${TEST_PASS_DIR}/test-matrix.yaml" | sort -u)
IMAGE_FILTER=$(printf '%s\n' "${required_baseline_ids[@]}" "${required_impl_ids[@]}" | sort -u | paste -sd'|')
```

Result: `IMAGE_FILTER="iperf|rust-v0.56|go-v0.45"`

### Step 3: Call build orchestrator

From `perf/run.sh:554-555`:
```bash
build_images_from_section "baselines" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
```

### Step 4: Generate build YAML for each image

For rust-v0.56, from `perf/images.yaml:127-142`:
```yaml
implementations:
  - id: rust-v0.56
    name: "rust-libp2p v0.56"
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

Generates `/srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml`:
```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
```

### Step 5: Execute build

From `lib/lib-image-building.sh:151`:
```bash
bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "$yaml_file"
```

### Step 6: Build executor runs

`lib/build-single-image.sh`:
1. Loads YAML with `yq`
2. Checks if image exists
3. Calls `build_from_local()`
4. Shows result

### Step 7: Build function executes

`lib/lib-image-building.sh:393-425`:
```bash
docker build -f "images/rust/v0.56/Dockerfile" -t "perf-rust-v0.56" "images/rust/v0.56"
```

### Step 8: Result displayed

```
===============================================================================
Building: perf-rust-v0.56
===============================================================================
    Type: local
    Path: images/rust/v0.56
    Building Docker image...
    #0 building with "default" instance using docker driver
    [... Docker output ...]
    ✓ Built: perf-rust-v0.56
    ✓ Image ID: a3f7b21c1d4e...
```

---

## Implementation Status

### Currently Implemented ✅

- ✅ **Local builds** - All perf implementations use this
- ✅ **GitHub snapshot builds** - Implemented, not used in perf
- ✅ **GitHub with submodules** - Implemented, not used in perf
- ✅ **Browser builds** - Implemented, not used in perf
- ✅ **Image caching** - Skip build if image exists
- ✅ **GitHub caching** - Snapshots and git repos cached
- ✅ **Output formatting** - clean, indented, filtered styles
- ✅ **YAML-based interface** - Consistent across all builds
- ✅ **Automatic orchestration** - Called from test runner

### Not Implemented ❌

- ❌ **Remote builds** - Code exists but is commented out
- ❌ **Multi-platform builds** - Not implemented
- ❌ **Custom build arguments** - Not implemented
- ❌ **Registry push** - Not implemented

---

## File Reference

### Core Build System

| File | Lines | Purpose |
|------|-------|---------|
| `lib/build-single-image.sh` | 108 | YAML executor - reads YAML and delegates to build functions |
| `lib/lib-image-building.sh` | 491 | Build implementation - all source type handlers |
| `lib/lib-output-formatting.sh` | 6066 bytes | Print functions for consistent output |

### Perf Integration

| File | Lines | Purpose |
|------|-------|---------|
| `perf/run.sh` | 841 | Test runner - orchestrates builds at lines 535-561 |
| `perf/images.yaml` | 181 | Implementation definitions |

### Cache Locations

| Location | Purpose |
|----------|---------|
| `/srv/cache/snapshots/` | GitHub snapshot zips |
| `/srv/cache/git-repos/` | Git clones with submodules |
| `/srv/cache/build-yamls/` | Generated build YAML files |

---

## Usage Examples

### Example 1: Normal Test Run

```bash
cd perf
./run.sh --test-ignore "experimental"
```

**What happens:**
1. Test matrix generated (determines required images)
2. `build_images_from_section()` called for baselines and implementations
3. For each required image:
   - Check if image exists (skip if yes)
   - Generate build YAML
   - Execute `lib/build-single-image.sh`
4. Continue with test execution

### Example 2: Force Rebuild

```bash
cd perf
./run.sh --force-image-rebuild --test-ignore "experimental"
```

**What changes:**
- `forceRebuild: true` in generated YAML
- Image existence check skipped
- All images rebuilt even if they exist

### Example 3: Manual Build

```bash
# Create custom build YAML
cat > /tmp/my-rust-build.yaml <<EOF
imageName: my-rust-test
imageType: peer
imagePrefix: test
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: perf/images/rust/v0.56
  dockerfile: Dockerfile
EOF

# Execute build
./lib/build-single-image.sh /tmp/my-rust-build.yaml
```

### Example 4: Debug Build Failure

```bash
# 1. Find the generated YAML
ls /srv/cache/build-yamls/docker-build-perf-*.yaml

# 2. Inspect parameters
cat /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml

# 3. Rerun with debug
bash -x ./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
```

---

## Related Documentation

- **docker_build_yaml_schema.md** - Complete YAML schema reference
- **inputs-schema.md** - inputs.yaml specification
- **CLAUDE.md** - Comprehensive codebase guide

---

## Design Principles

### 1. YAML-Based Configuration

**Why:** Declarative, human-readable, easy to inspect and debug

**Implementation:**
- All build parameters in YAML files
- Generated by orchestrator, consumed by executor
- Stored in cache for debugging

### 2. Separation of Concerns

**Orchestrator** (perf/run.sh + lib-image-building.sh):
- Reads images.yaml
- Determines what to build
- Generates build YAML files

**Executor** (lib/build-single-image.sh):
- Reads build YAML
- Validates parameters
- Executes build

**Build Functions** (lib/lib-image-building.sh):
- Source-specific implementation
- Caching logic
- Error handling

### 3. Aggressive Caching

**Multiple cache levels:**
- Docker image layer cache (Docker's built-in)
- Image existence check (skip if already built)
- GitHub snapshot cache (download once)
- Git repo cache (clone with submodules once)

**Result:** Significantly faster repeated builds

### 4. Consistent Output

**All builds show:**
- Clear section headers
- Progress indicators
- Success/failure status
- Image ID on completion

**Benefits:**
- Easy to follow build progress
- Consistent user experience
- Easier debugging

---

## Quick Reference

```bash
# Run perf tests (builds images automatically)
cd perf
./run.sh --test-ignore "experimental"

# Force rebuild all images
./run.sh --force-image-rebuild

# Build specific implementation manually
./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml

# Inspect build parameters
cat /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml

# Debug build
bash -x ./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml

# Clear build cache (force rebuild next time)
rm -rf /srv/cache/build-yamls/*

# Clear GitHub cache (force re-download)
rm -rf /srv/cache/snapshots/*
rm -rf /srv/cache/git-repos/*
```
