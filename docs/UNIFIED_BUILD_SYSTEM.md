# Unified Docker Image Build System

YAML-based Docker image build system used by all test suites (transport, perf, hole-punch).

---

## Quick Start

### Build Images for a Test Suite

```bash
# Transport tests
cd transport
bash lib/build-images.sh "rust-v0.56" "false"

# Perf tests
cd perf
bash lib/build-images.sh "go-v0.45|rust-v0.56" "false"

# Hole-punch tests (relay + router + peer)
cd hole-punch
bash lib/build-images.sh "linux" "linux" "linux" "false"
```

### Build a Single Image Manually

```bash
# 1. Create YAML file
cat > /tmp/my-build.yaml <<EOF
imageName: test-rust-v0.56
imageType: peer
imagePrefix: test-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/perf/impls/rust/v0.56
  dockerfile: Dockerfile
EOF

# 2. Build
./lib/build-single-image.sh /tmp/my-build.yaml
```

---

## Architecture

```
               ┌─────────────────────────────────┐
               │   Test Suite Orchestrators      │
               │  (Creates YAML, decides loc)    │
               └────────────────┬────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌──────▼──────┐ ┌────────▼────────┐
    │    Transport     │ │    Perf     │ │  Hole-Punch     │
    │  build-images.sh │ │build-images │ │ build-images.sh │
    │   (138 lines)    │ │  (171 lines)│ │   (148 lines)   │
    └─────────┬────────┘ └──────┬──────┘ └────────┬────────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
                   ┌────────────▼─────────────┐
                   │  build-single-image.sh   │
                   │    (YAML Executor)       │
                   │      (87 lines)          │
                   └────────────┬─────────────┘
                                │
               ┌────────────────┼────────────────┐
               │                │                │
      ┌────────▼────────┐ ┌─────▼───────┐ ┌──────▼────────┐
      │lib-image-       │ │lib-remote-  │ │Docker Registry│
      │building.sh      │ │execution.sh │ │               │
      │(183 lines)      │ │(157 lines)  │ │               │
      └─────────────────┘ └─────────────┘ └───────────────┘
```

---

## Key Components

### 1. Orchestrators (Test-Specific)
**Location:** `<test>/lib/build-images.sh`

**Purpose:**
- Read `impls.yaml`
- Apply filters
- Create YAML files for each image
- Call executor (local or remote)

**Examples:**
- `transport/lib/build-images.sh` - 138 lines
- `perf/lib/build-images.sh` - 171 lines (with remote support)
- `hole-punch/lib/build-images.sh` - 148 lines (relay/router/peer)

### 2. Executor (Shared)
**Location:** `lib/build-single-image.sh`

**Purpose:**
- Read YAML parameters
- Validate inputs
- Delegate to build functions
- Show clean output with image ID

**Lines:** 87 (reused by all test suites)

### 3. Build Functions (Shared)
**Location:** `lib/lib-image-building.sh`

**Functions:**
- `download_github_snapshot()` - GitHub caching
- `extract_github_snapshot()` - Extraction
- `build_from_github()` - GitHub builds
- `build_from_local()` - Local builds
- `build_browser_image()` - Browser builds
- `get_output_filter()` - Output styling

**Lines:** 183 (reused by all test suites)

### 4. Remote Execution (Shared)
**Location:** `lib/lib-remote-execution.sh`

**Functions:**
- `test_ssh_connectivity()` - Test single server
- `test_all_remote_servers()` - Test all servers
- `build_on_remote()` - Execute remote build
- `copy_to_remote()` - SCP utility
- `exec_on_remote()` - SSH utility

**Lines:** 157 (used by perf, available to all)

---

## Supported Features

### ✅ Source Types
- **GitHub** - Download snapshots, cached locally
- **Local** - Build from filesystem
- **Browser** - Chromium, Firefox, WebKit

### ✅ Build Locations
- **Local** - Build on current machine
- **Remote** - Build on remote server via SSH

### ✅ Image Types
- **Peer** - Regular implementations
- **Relay** - Hole-punch relays
- **Router** - Hole-punch routers

### ✅ Output Styles
- **Clean** - Full docker output (recommended)
- **Indented** - 4-space indentation
- **Filtered** - Only steps and errors

---

## Benefits

### Code Reuse
- **Shared code:** 427 lines (executor + libraries)
- **Used by:** 3 test suites (effective 3x reuse)
- **Maintenance:** Fix bugs once, all tests benefit

### Consistent UX
All test suites show the same clean aesthetic:
```
╲ Building: transport-interop-rust-v0.56
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Type: github
→ Repo: libp2p/rust-libp2p
→ Commit: 70082df7
  ✓ [HIT] Using cached snapshot: 70082df7.zip
→ Extracting snapshot...
→ Building Docker image...
[... docker output ...]
✓ Built: transport-interop-rust-v0.56
✓ Image ID: fb3ff19c3577...
```

### Easy Debugging
```bash
# Inspect build parameters
cat /srv/cache/build-yamls/docker-build-rust-v0.56.yaml

# Rerun single build
./lib/build-single-image.sh /srv/cache/build-yamls/docker-build-rust-v0.56.yaml

# Debug mode
bash -x ./lib/build-single-image.sh <yaml>
```

### Remote Builds
```bash
# Builds on remote servers look identical to local builds
# Output streams in real-time with formatting preserved
# No special handling needed in orchestrator
```

---

## Documentation

### Reference Docs
- **YAML Schema:** `/srv/test-plans/docs/DOCKER_BUILD_YAML_SCHEMA.md`
- **Troubleshooting:** `/srv/test-plans/docs/BUILD_SYSTEM_TROUBLESHOOTING.md`
- **Migration Guide:** `/srv/test-plans/docs/ADDING_NEW_TEST_SUITE.md`

### Implementation Plans
- **Architecture:** `/srv/test-plans/UNIFIED_BUILD_SYSTEM_PLAN.md`
- **Phase 1:** `/srv/test-plans/PHASE1_COMPLETE.md` - Core infrastructure
- **Phase 2:** `/srv/test-plans/PHASE2_COMPLETE.md` - Transport refactor
- **Phase 3:** `/srv/test-plans/PHASE3_COMPLETE.md` - Perf refactor
- **Phase 4:** `/srv/test-plans/PHASE4_COMPLETE.md` - Hole-punch refactor
- **Phase 5:** `/srv/test-plans/PHASE5_COMPLETE.md` - Documentation

---

## Quick Reference

```bash
# Build all images for transport
cd transport && bash lib/build-images.sh

# Build specific images for perf
cd perf && bash lib/build-images.sh "go-v0.45|rust-v0.56" "false"

# Force rebuild hole-punch relay
cd hole-punch && bash lib/build-images.sh "linux" "" "" "true"

# Test single image build
./lib/build-single-image.sh /srv/cache/build-yamls/<name>.yaml

# Run integration tests
./tests/test-unified-build-system.sh

# Check dependencies
./run_tests.sh --check-deps

# Test remote connectivity (perf)
cd perf
source lib/lib-perf.sh
source ../lib/lib-remote-execution.sh
test_all_remote_servers impls.yaml get_server_config get_remote_hostname get_remote_username is_remote_server
```

