# Source Types in impls.yaml

This document explains the 3 source types supported in `impls.yaml`.

## Overview

The `source.type` field determines how the implementation is built:

1. **`github`** - Download from GitHub repository (using commit SHA)
2. **`local`** - Build from local Dockerfile in this repository
3. **`browser`** - Multi-stage build that depends on a base image

## 1. GitHub Type

**Purpose**: Download source code from a GitHub repository and build

### Standard GitHub Build

```yaml
- id: rust-v0.53
  source:
    type: github
    repo: libp2p/rust-libp2p
    commit: b7914e407da34c99fb76dcc300b3d44b9af97fac  # Full 40-char SHA-1
    dockerfile: interop-tests/Dockerfile.native
  transports: [tcp, ws, quic-v1]
  secureChannels: [noise, tls]
  muxers: [yamux, mplex]
```

**Build process:**
1. Download: `https://github.com/libp2p/rust-libp2p/archive/b7914e407da34c99fb76dcc300b3d44b9af97fac.zip`
2. Cache at: `/srv/cache/snapshots/b7914e407da34c99fb76dcc300b3d44b9af97fac.zip`
3. Extract to temp directory: `rust-libp2p-b7914e407da34c99fb76dcc300b3d44b9af97fac/`
4. Build: `docker build -f interop-tests/Dockerfile.native .`
5. Tag: `rust-v0.53`

**Fields:**
- `repo` (required) - GitHub repository in format `owner/repo`
- `commit` (required) - Full 40-character SHA-1 commit hash
- `dockerfile` (required) - Path to Dockerfile relative to repository root

**Download URL**: `https://github.com/{repo}/archive/{commit}.zip`

**Build process:**
1. Download: `https://github.com/{repo}/archive/{commit}.zip`
2. Cache at: `/srv/cache/snapshots/{commit}.zip`
3. Extract to temp directory: `{repo-name}-{commit}/`
4. Build: `docker build -f {extracted-dir}/{dockerfile} {extracted-dir}`
5. Tag: `{id}`

**Note**: All implementations use 40-character commit SHAs for consistency. Even Go implementations (which use version tags in the original) have been converted to use the commit SHA that corresponds to each version tag.

### GitHub with Local Dockerfile

```yaml
- id: python-v0.4
  source:
    type: github
    repo: libp2p/py-libp2p
    commit: 09d0064f1d1dbee64a148d72374ed51ecc80ad4d
    dockerfile: Dockerfile
    buildContext: local  # Use local Dockerfile, not from repo
```

**Build process:**
1. Download repo from GitHub (same as standard)
2. Extract to temp directory
3. **Use local Dockerfile**: `impls/python/v0.4/Dockerfile` (not from downloaded repo)
4. Build with downloaded source as context

**When to use**: When you need a custom Dockerfile that's not in the upstream repository

---

## 2. Local Type

**Purpose**: Build from a Dockerfile that's already in this repository (no download needed)

```yaml
- id: js-v3.x
  source:
    type: local
    path: impls/js/v3.x
    dockerfile: Dockerfile
  transports: [tcp, ws, wss]
  secureChannels: [noise]
  muxers: [mplex, yamux]
  dialOnly: [wss]
```

**Build process:**
1. Change to path: `cd impls/js/v3.x`
2. Build: `docker build -f Dockerfile -t js-v3.x .`
3. No download, no extraction needed

**Fields:**
- `path` (required) - Path relative to transport-interop-v2/ directory
- `dockerfile` (required) - Dockerfile name (usually just `Dockerfile`)

**When to use**:
- Implementation code is in this repository
- Frequent changes during development
- Doesn't make sense to download from external repo

**Examples**: JavaScript implementations (v1.x, v2.x, v3.x)

---

## 3. Browser Type

**Purpose**: Build a browser-based test container that depends on a Node.js or native base image

```yaml
- id: chromium-js-v2.x
  source:
    type: browser
    baseImage: js-v2.x        # Must be built first
    browser: chromium          # chromium, firefox, or webkit
    dockerfile: impls/js/v2.x/BrowserDockerfile
  transports: [webtransport, wss, webrtc-direct, webrtc]
  secureChannels: [noise]
  muxers: [mplex, yamux]
  dialOnly: [webtransport, wss, webrtc-direct]
```

**Build process:**
1. **Prerequisite**: Build base image first (e.g., `js-v2.x`)
2. Tag base image: `docker tag js-v2.x node-js-v2.x`
3. Build browser image:
   ```bash
   docker build \
     -f impls/js/v2.x/BrowserDockerfile \
     --build-arg BASE_IMAGE=node-js-v2.x \
     --build-arg BROWSER=chromium \
     -t chromium-js-v2.x \
     impls/js/v2.x
   ```

**Fields:**
- `baseImage` (required) - ID of base implementation (must exist in impls.yaml)
- `browser` (required) - Browser type: `chromium`, `firefox`, or `webkit`
- `dockerfile` (required) - Path to BrowserDockerfile

**When to use**: Browser-based tests using Playwright/Puppeteer

**Examples**:
- Chromium-JS (v1.x, v2.x)
- Firefox-JS (v1.x, v2.x)
- WebKit-JS (v1.x, v2.x)
- Chromium-Rust (v0.53, v0.54)

---

## Additional Fields

### `dialOnly`

**Purpose**: Specify which transports can only be used for dialing (not listening)

```yaml
dialOnly: [wss, webtransport, webrtc-direct]
```

**Meaning**:
- This implementation can dial using these transports
- It cannot listen on these transports
- Test matrix generation should skip this implementation as listener for these transports

**Used by**: Browser implementations (browsers can't listen for incoming connections)

### `requiresSubmodules`

**Purpose**: Repository needs git submodules

```yaml
- id: c-v0.0.1
  source:
    type: github
    repo: Pier-Two/c-libp2p
    commit: 23a617223a3bbfb4b2af8f219f389e440b9c1ac2
    requiresSubmodules: true
```

**Build process**: Use `git clone --recursive` instead of downloading zip

### `complexBuild`

**Purpose**: Build has special requirements beyond standard Docker build

```yaml
complexBuild: true
```

**Meaning**: Implementation may need special handling (documented in impl directory)

---

## Build Script Requirements

The `build-images.sh` script must handle all 3 types:

```bash
case "$source_type" in
    github)
        # Download from GitHub using commit SHA
        # Extract and build
        ;;

    local)
        # Build from local directory
        # No download needed
        ;;

    browser)
        # Ensure base image built first
        # Tag base image
        # Build with --build-arg
        ;;
esac
```

## Summary Table

| Type | Download? | Build Context | Use Case | Examples |
|------|-----------|---------------|----------|----------|
| **github** | Yes | Downloaded repo | Most implementations | Rust, Go, Python, etc. |
| **local** | No | Local directory | In-repo implementations | JavaScript v1.x, v2.x, v3.x |
| **browser** | No | Local directory | Browser tests | Chromium-JS, Firefox-JS |

## Migration Notes

**Old system used**:
- Makefiles with wget/git clone
- Mixed approaches (some version tags, some commits)
- Inconsistent handling

**New system uses**:
- Single `impls.yaml` with explicit types
- Consistent commit SHAs for GitHub
- Clear separation of local vs remote builds
- Explicit browser build dependencies

**Benefits**:
- Easier to understand
- Consistent caching (commit SHAs)
- Clear build order (browser dependencies)
- No Makefiles to maintain
