# Docker Build YAML Schema

Complete reference for the YAML-based Docker image build system used by all test suites (perf, transport, hole-punch).

This documentation is based on the actual implementation in `lib/build-single-image.sh` and `lib/lib-image-building.sh`.

---

## Overview

The build system uses YAML files to define Docker image build parameters. These files are:

1. **Generated automatically** by `build_images_from_section()` in `lib/lib-image-building.sh:23-157`
2. **Stored in** `$CACHE_DIR/build-yamls/docker-build-perf-<id>.yaml` (or transport/hole-punch)
3. **Consumed by** `lib/build-single-image.sh` to execute builds

**Used by all test suites:**
- **perf**: Builds `baselines` + `implementations`
- **transport**: Builds `implementations` only
- **hole-punch**: Builds `routers` + `relays` + `implementations`

### Example Paths

**Note**: All YAML files are currently named with `docker-build-perf-` prefix regardless of test suite (see lib/lib-image-building.sh:60). The resulting Docker images use the correct test type prefix.

```
# Examples (all test suites use same YAML naming):
/srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml       # Implementation
/srv/cache/build-yamls/docker-build-perf-iperf.yaml            # Baseline (perf only)
/srv/cache/build-yamls/docker-build-perf-linux.yaml            # Router (hole-punch only)
```

### Image Naming

Docker images are named using the pattern: `<test-type>-<section>-<id>`

```
# Perf test suite
perf-implementations-rust-v0.56      # Implementation
perf-baselines-iperf                 # Baseline

# Transport test suite
transport-implementations-go-v0.45   # Implementation

# Hole-punch test suite
hole-punch-implementations-rust-v0.56   # Peer implementation
hole-punch-routers-linux                # NAT router
hole-punch-relays-rust-v0.56            # Relay server
```

---

## Schema Structure

### Required Fields

```yaml
imageName: string                    # Full Docker image name (e.g., "perf-rust-v0.56")
imageType: peer                      # Type of image (currently always "peer")
imagePrefix: string                  # Prefix for image names (e.g., "perf")
sourceType: github|local|browser    # Build method
buildLocation: local                 # Always "local" (remote is not implemented)
cacheDir: string                     # Absolute path to cache directory
forceRebuild: bool                   # true = rebuild even if exists
```

### Source Type Sections

Depending on `sourceType`, one of these sections is required:

- `github:` - For GitHub repository sources
- `local:` - For local filesystem sources
- `browser:` - For browser-based builds (not used in perf)

---

## Source Type: Local

Used for implementations built from local filesystem. **This is the primary source type used in perf and hole-punch tests.**

### YAML Structure

```yaml
sourceType: local

local:
  path: string                       # Absolute or relative path to source directory
  dockerfile: string                 # Dockerfile name (default: "Dockerfile")
  patchPath: string                  # Optional: Directory containing patch file (relative to run.sh PWD or absolute)
  patchFile: string                  # Optional: Patch filename (no path separators, must be in patchPath directory)
```

### Example: Rust Implementation (from perf/images.yaml)

**images.yaml entry:**
```yaml
implementations:
  - id: rust-v0.56
    name: "rust-libp2p v0.56"
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile
    server: local
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

**Generated build YAML** (`/srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml`):
```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
  patchPath: ""
  patchFile: ""
```

### Build Process (lib/lib-image-building.sh:485-535)

1. **Validate path exists**
   ```bash
   if [ ! -d "$local_path" ]; then
     print_error "Local path not found: $local_path"
     return 1
   fi
   ```

2. **Apply patch if specified** (lines 501-518)
   - If both `patchPath` and `patchFile` are specified, create temporary copy of source
   - Apply patch to temporary copy using `apply_patch_if_specified()`
   - Build from temporary copy, then cleanup

3. **Build Docker image**
   ```bash
   docker build -f "$build_path/$dockerfile" -t "$image_name" "$build_path"
   ```

---

## Source Type: GitHub

Used for implementations built from GitHub repositories. **This is the primary source type used in transport tests.**

### YAML Structure

```yaml
sourceType: github

github:
  repo: string                       # GitHub repo (e.g., "libp2p/rust-libp2p")
  commit: string                     # Full commit hash (40 chars)
  dockerfile: string                 # Path to Dockerfile in repo
  buildContext: string               # Build context path (default: ".")
  patchPath: string                  # Optional: Directory containing patch file (relative to run.sh PWD or absolute)
  patchFile: string                  # Optional: Patch filename (no path separators, must be in patchPath directory)

requiresSubmodules: bool             # true = use git clone with submodules
```

### Example: Rust from GitHub

```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf
sourceType: github
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false

github:
  repo: libp2p/rust-libp2p
  commit: 70082df7e6181722630eabc5de5373733aac9a21
  dockerfile: interop-tests/Dockerfile
  buildContext: .
  patchPath: images/rust/v0.56
  patchFile: transport-fix.patch

requiresSubmodules: false
```

### Build Process (Two Methods)

#### Method 1: Download Snapshot (requiresSubmodules: false)

Used when submodules are not needed (lib/lib-image-building.sh:385-434).

1. **Check cache** for `$CACHE_DIR/snapshots/<commit>.zip`
2. **Download if missing** (lib/lib-image-building.sh:173-195):
   ```bash
   wget -q -O "$snapshot_file" "https://github.com/$repo/archive/$commit.zip"
   ```
3. **Extract to temp directory** (lib/lib-image-building.sh:198-224):
   ```bash
   unzip -q "$snapshot_file" -d "$work_dir"
   # Creates: $work_dir/$repo_name-$commit/
   ```
4. **Apply patch if specified** (lines 418-422):
   ```bash
   apply_patch_if_specified "$context_dir" "$patch_path" "$patch_file"
   ```
5. **Build Docker image**:
   ```bash
   docker build \
     -f "$extracted_dir/$dockerfile" \
     -t "$image_name" \
     "$context_dir"
   ```
6. **Cleanup**: Remove temp directory

#### Method 2: Git Clone with Submodules (requiresSubmodules: true)

Used when submodules are required (lib/lib-image-building.sh:437-482).

1. **Check cache** for `$CACHE_DIR/git-repos/$repo_name-$commit/`
2. **Clone if missing** (lib/lib-image-building.sh:308-382):
   ```bash
   git clone --depth 1 "https://github.com/$repo.git" "$clone_dir"
   cd "$clone_dir"
   git fetch --depth 1 origin "$commit"
   git checkout "$commit"
   git submodule update --init --recursive --depth 1
   ```
3. **Cache the clone** for future use
4. **Copy to temp directory** (avoid modifying cache)
5. **Apply patch if specified** (lines 466-470):
   ```bash
   apply_patch_if_specified "$context_dir" "$patch_path" "$patch_file"
   ```
6. **Build Docker image**:
   ```bash
   docker build \
     -f "$cloned_dir/$dockerfile" \
     -t "$image_name" \
     "$context_dir"
   ```
7. **Cleanup**: Remove temp directory

### Cache Locations

- **Snapshots**: `$CACHE_DIR/snapshots/<commit-hash>.zip`
- **Git repos**: `$CACHE_DIR/git-repos/<repo-name>-<commit-hash>/`

---

## Test Suite Specific Sections

### Hole-Punch Test Sections

The hole-punch test suite has three unique sections defined in `hole-punch/images.yaml`:

1. **routers** - NAT router implementations
   - Currently: `linux` (Linux-based NAT router with iptables)
   - Used to simulate NAT devices that peers are behind
   - Image name: `hole-punch-routers-<id>`

2. **relays** - Relay server implementations
   - Currently: `rust-v0.56` (rust-libp2p relay server)
   - Provides relay functionality for DCUtR protocol
   - Image name: `hole-punch-relays-<id>`

3. **implementations** - Peer implementations
   - libp2p peers that will establish direct connections
   - Image name: `hole-punch-implementations-<id>`

**Example hole-punch images.yaml:**
```yaml
routers:
  - id: linux
    source:
      type: local
      path: images/linux
      dockerfile: Dockerfile

relays:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile.relay
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

implementations:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile.peer
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

---

## Source Type: Browser

Used for browser-based implementations. **Supported and used extensively in transport tests.**

### YAML Structure

```yaml
sourceType: browser

browser:
  baseImage: string                  # Base implementation ID
  browser: chromium|firefox|webkit   # Browser type
  dockerfile: string                 # Path to browser Dockerfile
  buildContext: string               # Build context directory
  patchPath: string                  # Optional: Directory containing patch file (relative to run.sh PWD or absolute)
  patchFile: string                  # Optional: Patch filename (no path separators, must be in patchPath directory)
```

### Example: Chromium Browser Build

```yaml
imageName: transport-chromium-js-v3.x
imageType: peer
imagePrefix: transport
sourceType: browser
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false

browser:
  baseImage: js-v3.x
  browser: chromium
  dockerfile: impls/js/v3.x/BrowserDockerfile
  buildContext: impls/js/v3.x
  patchPath: ""
  patchFile: ""
```

### Build Process (lib/lib-image-building.sh:538-609)

1. **Verify base image exists**: `<imagePrefix>-<baseImage>`
   ```bash
   base_image_name="transport-js-v3.x"
   docker image inspect "$base_image_name" &>/dev/null
   ```

2. **Tag base image** for browser build:
   ```bash
   docker tag "$base_image_name" "node-$base_image"
   ```

3. **Apply patch if specified** (lines 571-590):
   - If both `patchPath` and `patchFile` are specified, create temporary copy of build context
   - Apply patch to temporary copy
   - Update paths to use temporary copy

4. **Build browser image**:
   ```bash
   docker build \
     -f "$actual_dockerfile" \
     --build-arg BASE_IMAGE="node-$base_image" \
     --build-arg BROWSER="$browser" \
     -t "$image_name" \
     "$actual_build_context"
   ```

5. **Cleanup**: Remove temporary directory if created

### Supported Browsers

- `chromium` - Google Chromium
- `firefox` - Mozilla Firefox
- `webkit` - WebKit (Safari engine)

---

## Patch File Support

The build system supports applying patches to source code before building. This is useful for fixing bugs or applying customizations to upstream implementations without maintaining full forks.

### Usage in images.yaml

Add `patchPath` and `patchFile` to the `source` section:

```yaml
implementations:
  - id: rust-v0.56
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: 70082df7e6181722630eabc5de5373733aac9a21
      dockerfile: interop-tests/Dockerfile.native
      patchPath: images/rust/v0.56         # Directory containing the patch file
      patchFile: transport-fix.patch        # Patch filename (no path separators)
    transports: [ws, tcp, quic-v1]
    secureChannels: [tls, noise]
    muxers: [mplex, yamux]
```

### Patch File Requirements

1. **patchPath**: Directory containing the patch file
   - Can be absolute path (e.g., `/srv/patches`)
   - Can be relative to the test runner's working directory (e.g., `images/rust/v0.56`)
   - Resolved at build time

2. **patchFile**: Patch filename only (no path separators)
   - Must be a filename like `transport-fix.patch`
   - Cannot contain `/` or `\` characters
   - Must exist in the `patchPath` directory

3. **Patch Format**: Standard unified diff format
   - Generated with `git diff` or `diff -u`
   - Applied with `patch -p1` from inside the build context
   - Must be relative to the build context root

### How It Works (lib/lib-image-building.sh:226-304)

The `apply_patch_if_specified()` function:

1. **Validates** both patchPath and patchFile are specified
2. **Resolves** patchPath (handles absolute vs relative paths)
3. **Validates** patch file exists and is readable
4. **Creates** temporary copy of source (for local builds) or uses extracted/cloned directory
5. **Applies** patch: `cd <target> && patch -p1 < <patchfile>`
6. **Builds** Docker image from patched source
7. **Cleans up** temporary directories

### Example: Creating a Patch

```bash
# In the upstream repository
cd rust-libp2p

# Make your changes
vim interop-tests/src/lib.rs

# Generate patch
git diff > transport-fix.patch

# Copy to your test framework
cp transport-fix.patch /srv/test-plans/transport/images/rust/v0.56/
```

### Real-World Example

From `transport/images.yaml` (lines 69-79):

```yaml
- id: rust-v0.56
  source:
    type: github
    repo: libp2p/rust-libp2p
    commit: 70082df7e6181722630eabc5de5373733aac9a21
    dockerfile: interop-tests/Dockerfile.native
    patchPath: images/rust/v0.56
    patchFile: transport-fix.patch
  transports: [ws, tcp, quic-v1, webrtc-direct]
  secureChannels: [tls, noise]
  muxers: [mplex, yamux]
```

The patch file at `transport/images/rust/v0.56/transport-fix.patch` fixes a transport initialization issue.

---

## Generation Process

Build YAML files are generated automatically by `build_images_from_section()` in `lib/lib-image-building.sh:14-157`.

### Function Signature

```bash
build_images_from_section() {
  local section="$1"      # "implementations" or "baselines"
  local filter="${2:-}"   # Optional: pipe-separated filter (e.g., "rust-v0.56|go-v0.45")
  local force_image_rebuild="${3:-false}"
}
```

### Called From (perf/run.sh:554-555)

```bash
# Build baseline images
build_images_from_section "baselines" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

# Build implementation images
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
```

### Generation Flow

1. **Read images.yaml** to get implementation count:
   ```bash
   count=$(yq eval ".$section | length" "${IMAGES_YAML}")
   ```

2. **Iterate each implementation**:
   ```bash
   for ((i=0; i<count; i++)); do
     impl_id=$(yq eval ".${section}[$i].id" "${IMAGES_YAML}")
     source_type=$(yq eval ".${section}[$i].source.type" "${IMAGES_YAML}")
     # ...
   done
   ```

3. **Apply filter** (if specified):
   ```bash
   if [[ "$impl_id" == *"$pattern"* ]]; then
     match_found=true
   fi
   ```

4. **Check if image exists** (unless force rebuild):
   ```bash
   if docker_image_exists "$image_name"; then
     print_success "$image_name (already built)"
     continue
   fi
   ```

5. **Generate YAML file** at `$CACHE_DIR/build-yamls/docker-build-perf-${impl_id}.yaml`

6. **Execute build**:
   ```bash
   bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "$yaml_file"
   ```

---

## Execution: build-single-image.sh

The thin executor script that builds images from YAML files (lib/build-single-image.sh:1-108).

### Usage

```bash
./lib/build-single-image.sh <path-to-yaml-file>
```

### Execution Flow

1. **Validate arguments** (lines 8-14)
2. **Load YAML parameters** (lines 28-34):
   ```bash
   imageName=$(yq eval '.imageName' "$YAML_FILE")
   sourceType=$(yq eval '.sourceType' "$YAML_FILE")
   forceRebuild=$(yq eval '.forceRebuild' "$YAML_FILE")
   outputStyle=$(yq eval '.outputStyle' "$YAML_FILE")
   cacheDir=$(yq eval '.cacheDir' "$YAML_FILE")
   requiresSubmodules=$(yq eval '.requiresSubmodules // false' "$YAML_FILE")
   ```

3. **Check if already built** (lines 48-53):
   ```bash
   if [ "$forceRebuild" != "true" ]; then
     if docker image inspect "$imageName" &>/dev/null; then
       print_success "$imageName (already built)"
       exit 0
     fi
   fi
   ```

4. **Build based on source type** (lines 64-98):
   ```bash
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

5. **Display result** (lines 101-104):
   ```bash
   image_id=$(docker image inspect "$imageName" -f '{{.Id}}' | cut -d':' -f2)
   print_success "Built: $imageName"
   print_success "Image ID: ${image_id}..."
   ```

---

## Field Reference

### Top-Level Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `imageName` | string | Yes | Full Docker image name (e.g., "perf-rust-v0.56") | lib/lib-image-building.sh:66 |
| `imageType` | string | Yes | Type of image (always "peer" in current impl) | lib/lib-image-building.sh:67 |
| `imagePrefix` | string | Yes | Prefix for image names (e.g., "perf") | lib/lib-image-building.sh:68 |
| `sourceType` | string | Yes | Build method: "github", "local", or "browser" | lib/lib-image-building.sh:69 |
| `buildLocation` | string | Yes | Build location (always "local" in current impl) | lib/lib-image-building.sh:71 |
| `cacheDir` | string | Yes | Absolute path to cache directory | lib/lib-image-building.sh:71 |
| `forceRebuild` | bool | Yes | true = rebuild even if exists | lib/lib-image-building.sh:72 |

### GitHub Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `github.repo` | string | Yes | GitHub repo (e.g., "libp2p/rust-libp2p") | lib/lib-image-building.sh:89 |
| `github.commit` | string | Yes | Full commit hash (40 chars) | lib/lib-image-building.sh:90 |
| `github.dockerfile` | string | Yes | Path to Dockerfile in repo | lib/lib-image-building.sh:91 |
| `github.buildContext` | string | No | Build context path (default: ".") | lib/lib-image-building.sh:92 |
| `github.patchPath` | string | No | Directory containing patch file | lib/lib-image-building.sh:94 |
| `github.patchFile` | string | No | Patch filename (no path separators) | lib/lib-image-building.sh:95 |
| `requiresSubmodules` | bool | No | true = use git clone with submodules (default: false) | lib/lib-image-building.sh:93, 107 |

### Local Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `local.path` | string | Yes | Absolute or relative path to source directory | lib/lib-image-building.sh:112 |
| `local.dockerfile` | string | No | Dockerfile name (default: "Dockerfile") | lib/lib-image-building.sh:113 |
| `local.patchPath` | string | No | Directory containing patch file | lib/lib-image-building.sh:114 |
| `local.patchFile` | string | No | Patch filename (no path separators) | lib/lib-image-building.sh:115 |

### Browser Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `browser.baseImage` | string | Yes | Base implementation ID | lib/lib-image-building.sh:128 |
| `browser.browser` | string | Yes | Browser: "chromium", "firefox", or "webkit" | lib/lib-image-building.sh:129 |
| `browser.dockerfile` | string | Yes | Path to browser Dockerfile | lib/lib-image-building.sh:130 |
| `browser.buildContext` | string | Yes | Build context directory | lib/lib-image-building.sh:131 |
| `browser.patchPath` | string | No | Directory containing patch file | lib/lib-image-building.sh:132 |
| `browser.patchFile` | string | No | Patch filename (no path separators) | lib/lib-image-building.sh:133 |

---

## Usage Examples

### Example 1: Manual Build from YAML

```bash
# Create YAML file
cat > /tmp/build-rust.yaml <<EOF
imageName: test-rust-v0.56
imageType: peer
imagePrefix: test
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false

local:
  path: /srv/test-plans/perf/images/rust/v0.56
  dockerfile: Dockerfile
  patchPath: ""
  patchFile: ""
EOF

# Execute build
./lib/build-single-image.sh /tmp/build-rust.yaml
```

### Example 2: Automated Build (via perf/run.sh)

The build process is automatically triggered during a test run:

```bash
# Run perf tests - automatically builds required images
cd perf
./run.sh --test-ignore "experimental"
```

This internally calls:
```bash
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
```

Which generates YAML files and executes:
```bash
bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "$yaml_file"
```

### Example 3: Force Rebuild

```bash
cd perf
./run.sh --force-image-rebuild --test-ignore "experimental"
```

This sets `FORCE_IMAGE_REBUILD=true`, which is passed to `build_images_from_section()` and included in the generated YAML:
```yaml
forceRebuild: true
```

---

## Complete Perf Example

### images.yaml Entry (perf/images.yaml:127-142)

```yaml
implementations:
  - id: rust-v0.56
    name: "rust-libp2p v0.56"
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile
    server: local
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
    protocols: [perf]
    capabilities: [upload, download, latency]
    metadata:
      language: rust
      version: v0.56.0
      repo: libp2p/rust-libp2p
```

### Generated Build YAML

Location: `/srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml`

```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
  patchPath: ""
  patchFile: ""
```

### Build Execution

```bash
./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
```

Output:
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

---

## Implementation Status

### Currently Implemented and Used

- ✅ **Local builds** - Used by perf and hole-punch tests
- ✅ **GitHub snapshot builds** - Used by transport tests
- ✅ **GitHub with submodules** - Implemented, available when needed
- ✅ **Browser builds** - Used by transport tests for browser-based implementations
- ✅ **Image caching** - Skip build if image exists (unless force rebuild)
- ✅ **Patch file support** - Apply patches to source before building (all source types)
- ✅ **Snapshot caching** - GitHub snapshots cached in `/srv/cache/snapshots/`
- ✅ **Git repo caching** - Git clones with submodules cached in `/srv/cache/git-repos/`
- ✅ **Multi-section support** - Supports implementations, baselines, routers, relays

### Test Suite Usage

| Test Suite | Sections Built | Primary Source Type | Special Features |
|------------|----------------|---------------------|------------------|
| **perf** | baselines + implementations | local | Baseline comparisons (iperf, HTTPS, QUIC-Go) |
| **transport** | implementations | github | Browser builds, 40+ implementations, patches |
| **hole-punch** | routers + relays + implementations | local | NAT routers, relay servers, multiple Dockerfiles |

### Known Limitations

- **YAML file naming**: All build YAML files are named with `docker-build-perf-` prefix regardless of test suite (lib/lib-image-building.sh:60)
- **imageType field**: Always set to "peer" regardless of actual type (routers, relays, etc.)

---

## Related Files

### Core Build System
- **lib/build-single-image.sh** (~108 lines) - Thin executor for building from YAML
- **lib/lib-image-building.sh** (~610 lines) - Core build functions including patch support
- **lib/lib-output-formatting.sh** (~202 lines) - Print functions used during builds
- **lib/lib-github-snapshots.sh** (~615 lines) - GitHub snapshot download and caching

### Test Runners
- **perf/run.sh** (lines 479-498) - Build orchestration in perf test runner
- **transport/run.sh** (lines 479-498) - Build orchestration in transport test runner
- **hole-punch/run.sh** (lines 479-498) - Build orchestration in hole-punch test runner

### Configuration Files
- **perf/images.yaml** - Perf implementation definitions (baselines + implementations)
- **transport/images.yaml** - Transport implementation definitions (40+ implementations, GitHub sources, patches)
- **hole-punch/images.yaml** - Hole-punch definitions (routers + relays + implementations)

---

## See Also

- **[docs/inputs-schema.md](inputs-schema.md)** - inputs.yaml specification
- **[lib/README.md](../lib/README.md)** - Common library overview
- **[CLAUDE.md](../CLAUDE.md)** - Comprehensive framework documentation
- **[docs/write-a-perf-test-app.md](write-a-perf-test-app.md)** - How to write perf test applications
- **[docs/write-a-transport-test-app.md](write-a-transport-test-app.md)** - How to write transport test applications
- **[docs/write-a-hole-punch-test-app.md](write-a-hole-punch-test-app.md)** - How to write hole-punch test applications
