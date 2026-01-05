# Docker Build YAML Schema

Complete reference for the YAML-based Docker image build system used by the perf test suite.

This documentation is based on the actual implementation in `lib/build-single-image.sh` and `lib/lib-image-building.sh`.

---

## Overview

The build system uses YAML files to define Docker image build parameters. These files are:

1. **Generated automatically** by `build_images_from_section()` in `lib/lib-image-building.sh:14-157`
2. **Stored in** `$CACHE_DIR/build-yamls/docker-build-<test-type>-<id>.yaml`
3. **Consumed by** `lib/build-single-image.sh` to execute builds

### Example Path
```
/srv/cache/build-yamls/docker-build-perf-rust-v0.56.yaml
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
outputStyle: clean                   # Output formatting (always "clean" in perf)
```

### Source Type Sections

Depending on `sourceType`, one of these sections is required:

- `github:` - For GitHub repository sources
- `local:` - For local filesystem sources
- `browser:` - For browser-based builds (not used in perf)

---

## Source Type: Local

Used for implementations built from local filesystem. **This is the only source type currently used in perf tests.**

### YAML Structure

```yaml
sourceType: local

local:
  path: string                       # Absolute or relative path to source directory
  dockerfile: string                 # Dockerfile name (default: "Dockerfile")
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
outputStyle: clean

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
```

### Build Process (lib/lib-image-building.sh:393-425)

1. **Validate path exists**
   ```bash
   if [ ! -d "$local_path" ]; then
     print_error "Local path not found: $local_path"
     return 1
   fi
   ```

2. **Build Docker image**
   ```bash
   docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"
   ```

3. **Output handling**
   - `outputStyle: clean` → Full Docker output (unmodified)
   - Used by perf to maintain clean terminal output

---

## Source Type: GitHub

Used for implementations built from GitHub repositories. **Supported but not currently used in perf tests.**

### YAML Structure

```yaml
sourceType: github

github:
  repo: string                       # GitHub repo (e.g., "libp2p/rust-libp2p")
  commit: string                     # Full commit hash (40 chars)
  dockerfile: string                 # Path to Dockerfile in repo
  buildContext: string               # Build context path (default: ".")

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
outputStyle: clean

github:
  repo: libp2p/rust-libp2p
  commit: 70082df7e6181722630eabc5de5373733aac9a21
  dockerfile: interop-tests/Dockerfile
  buildContext: .

requiresSubmodules: false
```

### Build Process (Two Methods)

#### Method 1: Download Snapshot (requiresSubmodules: false)

Used when submodules are not needed (lib/lib-image-building.sh:287-338).

1. **Check cache** for `$CACHE_DIR/snapshots/<commit>.zip`
2. **Download if missing** (lib/lib-image-building.sh:160-182):
   ```bash
   wget -q -O "$snapshot_file" "https://github.com/$repo/archive/$commit.zip"
   ```
3. **Extract to temp directory** (lib/lib-image-building.sh:185-206):
   ```bash
   unzip -q "$snapshot_file" -d "$work_dir"
   # Creates: $work_dir/$repo_name-$commit/
   ```
4. **Build Docker image**:
   ```bash
   docker build \
     -f "$extracted_dir/$dockerfile" \
     -t "$image_name" \
     "$extracted_dir/$build_context"
   ```
5. **Cleanup**: Remove temp directory

#### Method 2: Git Clone with Submodules (requiresSubmodules: true)

Used when submodules are required (lib/lib-image-building.sh:341-390).

1. **Check cache** for `$CACHE_DIR/git-repos/$repo_name-$commit/`
2. **Clone if missing** (lib/lib-image-building.sh:210-284):
   ```bash
   git clone --depth 1 "https://github.com/$repo.git" "$clone_dir"
   cd "$clone_dir"
   git fetch --depth 1 origin "$commit"
   git checkout "$commit"
   git submodule update --init --recursive --depth 1
   ```
3. **Cache the clone** for future use
4. **Copy to temp directory** (avoid modifying cache)
5. **Build Docker image**:
   ```bash
   docker build \
     -f "$cloned_dir/$dockerfile" \
     -t "$image_name" \
     "$cloned_dir/$build_context"
   ```
6. **Cleanup**: Remove temp directory

### Cache Locations

- **Snapshots**: `$CACHE_DIR/snapshots/<commit-hash>.zip`
- **Git repos**: `$CACHE_DIR/git-repos/<repo-name>-<commit-hash>/`

---

## Source Type: Browser

Used for browser-based implementations. **Supported but not used in perf tests.**

### YAML Structure

```yaml
sourceType: browser

browser:
  baseImage: string                  # Base implementation ID
  browser: chromium|firefox|webkit   # Browser type
  dockerfile: string                 # Path to browser Dockerfile
  buildContext: string               # Build context directory
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
outputStyle: clean

browser:
  baseImage: js-v3.x
  browser: chromium
  dockerfile: impls/js/v3.x/BrowserDockerfile
  buildContext: impls/js/v3.x
```

### Build Process (lib/lib-image-building.sh:428-473)

1. **Verify base image exists**: `<imagePrefix>-<baseImage>`
   ```bash
   base_image_name="transport-js-v3.x"
   docker image inspect "$base_image_name" &>/dev/null
   ```

2. **Tag base image** for browser build:
   ```bash
   docker tag "$base_image_name" "node-$base_image"
   ```

3. **Build browser image**:
   ```bash
   docker build \
     -f "$dockerfile" \
     --build-arg BASE_IMAGE="node-$base_image" \
     --build-arg BROWSER="$browser" \
     -t "$image_name" \
     "$build_context"
   ```

### Supported Browsers

- `chromium` - Google Chromium
- `firefox` - Mozilla Firefox
- `webkit` - WebKit (Safari engine)

---

## Build Location: Remote

**Status**: Remote building is currently **NOT IMPLEMENTED** in the codebase.

The code for remote building exists but is commented out in `lib/lib-image-building.sh:41-50, 75-83, 141-148`.

### Implementation Notes

If remote building were enabled, it would:

1. Generate YAML file locally
2. SCP YAML file, build script, and libraries to remote server
3. Execute build remotely via SSH
4. Stream output back to local terminal
5. Cleanup remote files

### Requirements (if implemented)

- SSH key authentication configured
- Docker installed on remote server
- Same cache directory structure on remote
- `build_on_remote()` function in `lib/lib-remote-execution.sh`

---

## Output Styles

Controls Docker build output formatting (lib/lib-image-building.sh:476-490).

### `clean` (Default - Used by Perf)

Full Docker output, unmodified. Best for debugging.

```bash
# Implementation:
get_output_filter() {
  echo "cat"
}
```

Output:
```
#0 building with "default" instance using docker driver
#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 690B done
#1 DONE 0.0s
[... all docker output ...]
```

### `indented`

All output indented by 4 spaces. More compact.

```bash
# Implementation:
get_output_filter() {
  echo "sed 's/^/    /'"
}
```

Output:
```
    #0 building with "default" instance using docker driver
    #1 [internal] load build definition from Dockerfile
    [... indented output ...]
```

### `filtered`

Only shows step markers and errors. Most compact.

```bash
# Implementation:
get_output_filter() {
  echo "grep -E '^(#|Step|Successfully|ERROR)'"
}
```

Output:
```
#0 building with "default" instance using docker driver
Step 1/10 : FROM rust:alpine
Successfully built abc123def456
ERROR: failed to build
```

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
| `imageName` | string | Yes | Full Docker image name (e.g., "perf-rust-v0.56") | lib/lib-image-building.sh:64 |
| `imageType` | string | Yes | Type of image (always "peer" in current impl) | lib/lib-image-building.sh:65 |
| `imagePrefix` | string | Yes | Prefix for image names (e.g., "perf") | lib/lib-image-building.sh:66 |
| `sourceType` | string | Yes | Build method: "github", "local", or "browser" | lib/lib-image-building.sh:67 |
| `buildLocation` | string | Yes | Build location (always "local" in current impl) | lib/lib-image-building.sh:68 |
| `cacheDir` | string | Yes | Absolute path to cache directory | lib/lib-image-building.sh:69 |
| `forceRebuild` | bool | Yes | true = rebuild even if exists | lib/lib-image-building.sh:70 |
| `outputStyle` | string | Yes | Output formatting: "clean", "indented", "filtered" | lib/lib-image-building.sh:71 |

### GitHub Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `github.repo` | string | Yes | GitHub repo (e.g., "libp2p/rust-libp2p") | lib/lib-image-building.sh:88 |
| `github.commit` | string | Yes | Full commit hash (40 chars) | lib/lib-image-building.sh:89 |
| `github.dockerfile` | string | Yes | Path to Dockerfile in repo | lib/lib-image-building.sh:90 |
| `github.buildContext` | string | No | Build context path (default: ".") | lib/lib-image-building.sh:91 |
| `requiresSubmodules` | bool | No | true = use git clone with submodules (default: false) | lib/lib-image-building.sh:92, 102 |

### Local Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `local.path` | string | Yes | Absolute or relative path to source directory | lib/lib-image-building.sh:107 |
| `local.dockerfile` | string | No | Dockerfile name (default: "Dockerfile") | lib/lib-image-building.sh:108 |

### Browser Source Fields

| Field | Type | Required | Description | Source |
|-------|------|----------|-------------|--------|
| `browser.baseImage` | string | Yes | Base implementation ID | lib/lib-image-building.sh:119 |
| `browser.browser` | string | Yes | Browser: "chromium", "firefox", or "webkit" | lib/lib-image-building.sh:120 |
| `browser.dockerfile` | string | Yes | Path to browser Dockerfile | lib/lib-image-building.sh:121 |
| `browser.buildContext` | string | Yes | Build context directory | lib/lib-image-building.sh:122 |

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
outputStyle: clean

local:
  path: /srv/test-plans/perf/images/rust/v0.56
  dockerfile: Dockerfile
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
outputStyle: clean

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
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

- ✅ **Local builds** - Used by all perf implementations
- ✅ **GitHub snapshot builds** - Implemented, not currently used in perf
- ✅ **GitHub with submodules** - Implemented, not currently used in perf
- ✅ **Browser builds** - Implemented, not used in perf
- ✅ **Image caching** - Skip build if image exists (unless force rebuild)
- ✅ **Output formatting** - clean, indented, filtered styles
- ✅ **Snapshot caching** - GitHub snapshots cached in `/srv/cache/snapshots/`
- ✅ **Git repo caching** - Git clones with submodules cached in `/srv/cache/git-repos/`

### Not Implemented

- ❌ **Remote builds** - Code commented out (lib/lib-image-building.sh:41-50)
- ❌ **Multi-platform builds** - Not implemented
- ❌ **Custom build arguments** - Not implemented
- ❌ **Registry push** - Not implemented

---

## Related Files

- **lib/build-single-image.sh** (108 lines) - Thin executor for building from YAML
- **lib/lib-image-building.sh** (491 lines) - Core build functions
- **lib/lib-output-formatting.sh** - Print functions used during builds
- **perf/run.sh:535-561** - Build orchestration in test runner
- **perf/images.yaml** - Implementation definitions

---

## See Also

- **docs/inputs-schema.md** - inputs.yaml specification
- **docs/unified_build_system.md** - Unified build system documentation
- **lib/README.md** - Common library overview
