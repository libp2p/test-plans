# Migration from transport-interop to transport-interop-v2

This document describes the migration of all implementations from the original transport-interop to the new v2 architecture.

## Migration Summary

### ✅ Complete Migration

**Implementations Migrated**: 30 implementations across 10 languages

**Languages**:
- Rust: 4 versions (v0.53, v0.54, v0.55, v0.56)
- Go: 8 versions (v0.38-v0.45)
- JavaScript/Node.js: 3 versions (v1.x, v2.x, v3.x)
- Browser (Chromium-JS): 2 versions
- Browser (Firefox-JS): 2 versions
- Browser (WebKit-JS): 2 versions
- Browser (Chromium-Rust): 2 versions
- Python: 1 version (v0.4)
- Nim: 1 version (v1.14)
- JVM/Kotlin: 1 version (v1.2)
- C: 1 version (v0.0.1)
- .NET: 1 version (v1.0)
- Zig: 1 version (v0.0.1)
- Eth-P2P-Z: 1 version (v0.0.1)

**Total**: 30 implementations

## Translation Table

### Configuration Migration

| Old | New | Changes |
|-----|-----|---------|
| `versionsInput.json` | `impls.yaml` | JSON→YAML, added source metadata |
| `impl/` | `impls/` | Directory renamed |
| `impl/*/test-ignore.txt` | `impls/*/test-selection.yaml` | TXT→YAML, added test-filter |
| `impl/*/Makefile` | Removed | Info extracted to `impls.yaml` |
| `image.json` | `image.yaml` | JSON→YAML |

### Implementation Types

**Type 1: GitHub with Commit SHA** (most common)
```yaml
# Old: impl/rust/v0.53/Makefile
commitSha := b7914e407da34c99fb76dcc300b3d44b9af97fac

# New: impls.yaml
- id: rust-v0.53
  source:
    type: github
    repo: libp2p/rust-libp2p
    commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
    dockerfile: interop-tests/Dockerfile.native
```

**Type 2: GitHub with Version Tag** (Go)
```yaml
# Old: impl/go/v0.45/Makefile
version := 0.45.0

# New: impls.yaml
- id: go-v0.45
  source:
    type: github
    repo: libp2p/go-libp2p
    version: v0.45.0
    dockerfile: test-plans/PingDockerfile
```

**Type 3: Local Dockerfile** (JavaScript)
```yaml
# Old: impl/js/v3.x/Dockerfile (local file)

# New: impls.yaml
- id: js-v3.x
  source:
    type: local
    path: impls/js/v3.x
    dockerfile: Dockerfile
```

**Type 4: Browser** (special multi-stage builds)
```yaml
# Old: impl/js/v3.x/Makefile builds chromium/firefox/webkit images

# New: impls.yaml
- id: chromium-js-v3.x
  source:
    type: browser
    baseImage: js-v3.x
    browser: chromium
    dockerfile: impls/js/v3.x/BrowserDockerfile
```

## Implementation Details

### Rust Implementations

**Migrated**: 4 versions (v0.53, v0.54, v0.55, v0.56)

| Version | Commit (first 8) | Dockerfile |
|---------|------------------|------------|
| v0.53 | b7914e40 | interop-tests/Dockerfile.native |
| v0.54 | 1cf96b26 | interop-tests/Dockerfile.native |
| v0.55 | 9698607c | interop-tests/Dockerfile.native |
| v0.56 | 70082df7 | interop-tests/Dockerfile.native |

**Capabilities**: ws, tcp, quic-v1, webrtc-direct / tls, noise / mplex, yamux

### Go Implementations

**Migrated**: 8 versions (v0.38-v0.45)

All use:
- Repo: `libp2p/go-libp2p`
- Dockerfile: `test-plans/PingDockerfile`
- Transports: tcp, ws, wss, quic-v1, webtransport, webrtc-direct
- Secure: tls, noise
- Muxers: yamux only

**Note**: Go uses version tags (v0.45.0) instead of commit SHAs

### JavaScript Implementations

**Migrated**: 3 Node.js versions + 6 browser variants

**Node.js** (v1.x, v2.x, v3.x):
- Local Dockerfiles in `impls/js/vX.x/`
- Transports: tcp, ws, wss (dial-only)
- Secure: noise
- Muxers: mplex, yamux

**Browser variants**:
- Chromium-JS (v1.x, v2.x)
- Firefox-JS (v1.x, v2.x)
- WebKit-JS (v1.x, v2.x)
- All support: webtransport, wss, webrtc-direct, webrtc
- All dial-only (browsers can't listen)

### Other Languages

| Language | Versions | Repo | Notes |
|----------|----------|------|-------|
| **Python** | v0.4 | libp2p/py-libp2p | Local Dockerfile |
| **Nim** | v1.14 | status-im/nim-libp2p | tcp, ws only |
| **JVM** | v1.2 | libp2p/jvm-libp2p | Kotlin/JVM |
| **C** | v0.0.1 | Pier-Two/c-libp2p | Complex build (submodules) |
| **.NET** | v1.0 | NethermindEth/dotnet-libp2p | tcp only |
| **Zig** | v0.0.1 | marcopolo/zig-libp2p | quic-v1 only |

### Browser Rust Implementations

**Migrated**: Chromium-Rust (v0.53, v0.54)

Uses Rust backend in browser (WASM):
- Transports: webtransport, webrtc-direct, ws
- All dial-only
- Requires special browser container

## Directory Structure Changes

### Old Structure
```
transport-interop/
├── impl/
│   ├── rust/v0.53/Makefile
│   ├── go/v0.45/Makefile
│   ├── js/v3.x/Dockerfile
│   └── python/v0.4/Makefile
└── versionsInput.json
```

### New Structure
```
transport-interop-v2/
├── impls/
│   ├── rust/
│   │   ├── test-selection.yaml
│   │   └── README.md
│   ├── go/
│   │   ├── test-selection.yaml
│   │   └── README.md
│   ├── js/
│   │   ├── v1.x/ (copied with Dockerfiles)
│   │   ├── v2.x/
│   │   ├── v3.x/
│   │   ├── test-selection.yaml
│   │   └── README.md
│   ├── python/
│   │   ├── v0.4/ (copied with Dockerfile)
│   │   ├── test-selection.yaml
│   │   └── README.md
│   ├── nim/
│   │   ├── v1.14/ (copied)
│   │   └── test-selection.yaml
│   ├── jvm/
│   │   └── test-selection.yaml
│   ├── c/
│   │   └── test-selection.yaml
│   ├── dotnet/
│   │   └── test-selection.yaml
│   ├── zig/
│   │   └── test-selection.yaml
│   └── chromium-rust/
│       ├── v0.53/ (copied)
│       ├── v0.54/ (copied)
│       └── test-selection.yaml
└── impls.yaml  # Single source of truth
```

## Build Strategy Changes

### Old Approach
```bash
# Each implementation has Makefile
cd impl/rust/v0.53
make

# Makefile downloads, extracts, builds
# Stores result in image.json
```

### New Approach
```bash
# Central script reads impls.yaml
bash scripts/build-images.sh

# For each implementation:
#   - If type=github: download from GitHub
#   - If type=local: use local Dockerfile
#   - If type=browser: multi-stage build
# Stores result in image.yaml
```

## Special Cases

### 1. Go Implementations (Version Tags)

Go uses semantic version tags instead of commit SHAs:

```yaml
source:
  version: v0.45.0  # Not commit SHA
```

Build script must handle: `https://github.com/libp2p/go-libp2p/archive/v0.45.0.zip`

### 2. JavaScript Local Builds

JavaScript implementations are NOT downloaded from GitHub:

```yaml
source:
  type: local
  path: impls/js/v3.x
  dockerfile: Dockerfile
```

Build script must use local directory as build context.

### 3. Browser Implementations

Browser images depend on Node.js base images:

```yaml
source:
  type: browser
  baseImage: js-v3.x  # Must be built first
  browser: chromium
```

Build order:
1. Build Node.js image (js-v3.x)
2. Build browser image using Node.js as base

### 4. C Implementation (Complex)

C implementation requires git submodules and external dependencies:

```yaml
source:
  requiresSubmodules: true
  complexBuild: true
```

May need special handling in build script.

## Test Selection Updates

### Old Format (test-ignore.txt)
```
rust-v0.53|rust-v0.54
```

### New Format (test-selection.yaml)
```yaml
test-filter:
  - rust-v0.53
  - rust-v0.54

test-ignore:
  - rust-v0.53 x rust-v0.53
  - flaky
```

**Created test-selection.yaml for**:
- Global (root)
- rust
- go
- python
- js
- nim
- jvm
- c
- dotnet
- zig
- chromium-rust

## Migration Verification

### Counts

| Category | Count |
|----------|-------|
| **Total Implementations** | 30 |
| **GitHub Repos** | 22 |
| **Local Builds** | 3 (js-v1.x, v2.x, v3.x) |
| **Browser Variants** | 8 |
| **test-selection.yaml** | 11 (10 languages + global) |

### Implementation Breakdown by Language

| Language | Count | Source Type |
|----------|-------|-------------|
| Rust | 4 | GitHub (commit) |
| Go | 8 | GitHub (version) |
| JavaScript | 3 | Local |
| Python | 1 | GitHub (commit) |
| Nim | 1 | GitHub (commit) |
| JVM | 1 | GitHub (commit) |
| C | 1 | GitHub (commit) |
| .NET | 1 | GitHub (commit) |
| Zig | 1 | GitHub (commit) |
| Browsers (JS) | 6 | Browser (multi-stage) |
| Browsers (Rust) | 2 | Browser (multi-stage) |

## Known Issues and TODOs

### Build Script Enhancements Needed

The current `build-images.sh` needs updates for:

1. **Go version tags**: Handle `version: v0.45.0` instead of `commit:`
   ```bash
   if has version field:
       url="https://github.com/$repo/archive/$version.zip"
   else:
       url="https://github.com/$repo/archive/$commit.zip"
   ```

2. **Local builds**: Handle `type: local`
   ```bash
   if type == "local":
       docker build -f $path/$dockerfile $path
   ```

3. **Browser builds**: Handle `type: browser`
   ```bash
   if type == "browser":
       # Build base image first
       # Then build browser image with --build-arg
   ```

4. **Complex builds**: Handle C implementation's requirements
   ```bash
   if requiresSubmodules:
       git clone --recursive
   ```

### Test Generation Enhancements

Current `generate-tests.sh` handles 3D matrix but needs:

1. **dialOnly support**: Some transports can only dial
   ```yaml
   dialOnly: [wss, webtransport]
   ```

   Tests should:
   - Allow these as dialer
   - Skip these as listener

## File Copies

### Copied Directories

| Source | Destination | Size |
|--------|-------------|------|
| `impl/js/` | `impls/js/` | Full directory with v1.x, v2.x, v3.x |
| `impl/python/v0.4/` | `impls/python/v0.4/` | Dockerfile only |
| `impl/nim/` | `impls/nim/` | Full directory |
| `impl/chromium-rust/` | `impls/chromium-rust/` | Full directory |

### Not Copied (Build from GitHub)

These will be downloaded by `build-images.sh`:
- Rust implementations (all)
- Go implementations (all)
- JVM implementation
- C implementation
- .NET implementation
- Zig implementation

## Test Matrix Impact

### Estimated Test Counts

With all 30 implementations:

**Conservative estimate** (assuming 50% can interoperate):
- Base pairs: 30 × 30 = 900 possible pairs
- Practical pairs: ~450 (50% have common transports)
- Tests per pair: ~10-20 (depending on capabilities)
- **Total: 4,500 - 9,000 tests**

**This is LARGE!** Will require:
- Significant test time (~4-8 hours with 8 workers)
- Substantial cache storage (~10-20GB)
- Filtering for practical use

### Recommended Test Strategies

**For development**:
```bash
# Test single language
./run_tests.sh --test-filter "rust" --workers 8

# Test single version
./run_tests.sh --test-filter "rust-v0.56" --workers 4
```

**For CI** (per-language workflows):
```bash
# Rust CI
./run_tests.sh --kind rust --workers 8

# Go CI
./run_tests.sh --kind go --workers 8
```

**For full matrix** (nightly):
```bash
# Skip browsers (slow)
./run_tests.sh --test-ignore "chromium|firefox|webkit" --workers 16
```

## Next Steps

1. **Update build-images.sh** to handle:
   - Version tags (Go)
   - Local builds (JavaScript)
   - Browser builds (multi-stage)
   - Complex builds (C with submodules)

2. **Update generate-tests.sh** to handle:
   - `dialOnly` transports
   - Listener-only restrictions

3. **Test migration** with subset:
   ```bash
   ./run_tests.sh --test-filter "rust-v0.56|python-v0.4" --workers 2
   ```

4. **Validate** all implementations build successfully

5. **Create CI workflows** for each language

## Validation Checklist

```bash
# 1. Verify impls.yaml is valid
yq eval '.implementations | length' impls.yaml
# Should output: 30

# 2. Count test-selection files
find impls -name "test-selection.yaml" | wc -l
# Should output: 10 (one per language)

# 3. Check copied directories
ls impls/js/
# Should show: v1.x, v2.x, v3.x, test-selection.yaml

# 4. Try building (will need script updates)
bash scripts/build-images.sh rust-v0.53
```

## Benefits of Migration

### Before (TypeScript)
- 30 separate Makefiles to maintain
- versionsInput.json disconnected from build configs
- No caching of test matrices
- CSV results (not structured)
- No reproducibility (no snapshots)

### After (Bash + YAML)
- Single impls.yaml source of truth
- No Makefiles (simpler)
- Content-addressed caching
- YAML results (structured)
- Self-contained snapshots
- Better documentation

## Summary

✅ **30 implementations migrated** from original transport-interop
✅ **10 test-selection.yaml files** created (one per language)
✅ **impls.yaml** contains all source metadata
✅ **Implementation directories** copied where needed
✅ **Ready for enhanced build script** to handle all types

**Migration Status: CONFIGURATION COMPLETE**

Next: Update build-images.sh to handle all source types (version tags, local, browser, complex).
