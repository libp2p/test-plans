# Docker Build YAML Schema

Complete reference for the unified YAML-based Docker image build system used by transport, perf, and hole-punch test suites.

---

## Schema Overview

Build parameters are defined in YAML files located at:
```
$CACHE_DIR/build-yamls/docker-build-<name>.yaml
```

These YAML files are consumed by `lib/build-single-image.sh` to build Docker images.

---

## Required Fields

```yaml
imageName: string                    # Full Docker image name (with prefix)
imageType: peer|relay|router        # Type of image being built
imagePrefix: string                  # Prefix used for base image resolution
sourceType: github|local|browser    # Source type determines build method
buildLocation: local|remote         # Where to build (local or remote server)
cacheDir: string                    # Absolute path to cache directory
forceRebuild: bool                  # true = rebuild even if exists
outputStyle: clean|indented|filtered # Docker build output formatting
```

---

## Source Type: GitHub

For implementations built from GitHub repositories.

```yaml
sourceType: github

github:
  repo: string                      # GitHub repo (e.g., libp2p/rust-libp2p)
  commit: string                    # Full commit hash (40 chars)
  dockerfile: string                # Path to Dockerfile in repo
  buildContext: string              # Build context (default: ".")
```

### Example: Rust Implementation
```yaml
imageName: transport-interop-rust-v0.56
imageType: peer
imagePrefix: transport-interop-
sourceType: github
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

github:
  repo: libp2p/rust-libp2p
  commit: 70082df7e6181722630eabc5de5373733aac9a21
  dockerfile: interop-tests/Dockerfile.native
  buildContext: .
```

### Build Process:
1. Check cache: `$CACHE_DIR/snapshots/<commit>.zip`
2. Download if missing: `wget https://github.com/<repo>/archive/<commit>.zip`
3. Extract to temp directory
4. Build: `docker build -f <extracted>/<dockerfile> -t <imageName> <extracted>/<buildContext>`

---

## Source Type: Local

For implementations built from local filesystem.

```yaml
sourceType: local

local:
  path: string                      # Absolute or relative path to source
  dockerfile: string                # Dockerfile name (default: "Dockerfile")
```

### Example: Go Implementation
```yaml
imageName: perf-go-v0.45
imageType: peer
imagePrefix: perf-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/perf/impls/go/v0.45
  dockerfile: Dockerfile
```

### Build Process:
1. Verify path exists
2. Build: `docker build -f <path>/<dockerfile> -t <imageName> <path>`

---

## Source Type: Browser

For browser-based implementations (chromium, firefox, webkit).

```yaml
sourceType: browser

browser:
  baseImage: string                 # Base implementation ID
  browser: chromium|firefox|webkit  # Browser type
  dockerfile: string                # Path to browser Dockerfile
  buildContext: string              # Build context directory
```

### Example: Chromium Browser Implementation
```yaml
imageName: transport-interop-chromium-js-v3.x
imageType: peer
imagePrefix: transport-interop-
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

### Build Process:
1. Verify base image exists: `<imagePrefix><baseImage>`
2. Tag base image: `docker tag <imagePrefix><baseImage> node-<baseImage>`
3. Build: `docker build --build-arg BASE_IMAGE=node-<baseImage> --build-arg BROWSER=<browser> -t <imageName> <buildContext>`

### Supported Browsers:
- `chromium` - Google Chromium
- `firefox` - Mozilla Firefox
- `webkit` - WebKit (Safari engine)

---

## Build Location: Remote

For building on remote servers (perf tests).

```yaml
buildLocation: remote

remote:
  server: string                    # Server ID (from impls.yaml)
  hostname: string                  # SSH hostname
  username: string                  # SSH username
```

### Example: Remote Perf Build
```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf-
sourceType: local
buildLocation: remote
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

remote:
  server: perf-server-1
  hostname: perf1.example.com
  username: testuser

local:
  path: /srv/test-plans/perf/impls/rust/v0.56
  dockerfile: Dockerfile
```

### Remote Build Process:
1. SCP YAML file to remote: `scp build.yaml user@host:/tmp/`
2. SCP build script: `scp build-single-image.sh user@host:/tmp/`
3. SCP library: `scp lib-image-building.sh user@host:/tmp/`
4. Execute remotely: `ssh -tt user@host "bash /tmp/build-single-image.sh /tmp/build.yaml"`
5. Output streams back in real-time with formatting preserved
6. Cleanup remote files

**Requirements:**
- SSH key authentication configured
- Docker installed on remote server
- Same cache directory structure on remote

---

## Output Styles

Controls how docker build output is displayed.

```yaml
outputStyle: clean|indented|filtered
```

### `clean` (Default, Recommended)
Full docker output, unmodified. Best for debugging.
```
#0 building with "default" instance using docker driver
#1 [internal] load build definition from Dockerfile
#1 transferring dockerfile: 690B done
#1 DONE 0.0s
[... all docker output ...]
```

### `indented`
All output indented by 4 spaces. More compact.
```
    #0 building with "default" instance using docker driver
    #1 [internal] load build definition from Dockerfile
    #1 transferring dockerfile: 690B done
    [... indented output ...]
```

### `filtered`
Only shows step markers and errors. Most compact.
```
#0 building with "default" instance using docker driver
Step 1/10 : FROM rust:alpine
Successfully built abc123def456
ERROR: failed to build
```

---

## Complete Examples

### Transport Test (GitHub + Browser)

**Base Image (GitHub):**
```yaml
imageName: transport-interop-js-v3.x
imageType: peer
imagePrefix: transport-interop-
sourceType: github
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

github:
  repo: libp2p/js-libp2p
  commit: abc123def456789
  dockerfile: interop/Dockerfile
  buildContext: .
```

**Browser Image (depends on base):**
```yaml
imageName: transport-interop-chromium-js-v3.x
imageType: peer
imagePrefix: transport-interop-
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

---

### Perf Test (Local + Remote)

**Local Build:**
```yaml
imageName: perf-rust-v0.56
imageType: peer
imagePrefix: perf-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/perf/impls/rust/v0.56
  dockerfile: Dockerfile
```

**Remote Build:**
```yaml
imageName: perf-go-v0.45
imageType: peer
imagePrefix: perf-
sourceType: local
buildLocation: remote
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

remote:
  server: perf-server-1
  hostname: perf1.example.com
  username: testuser

local:
  path: /srv/test-plans/perf/impls/go/v0.45
  dockerfile: Dockerfile
```

---

### Hole-Punch Test (Relay/Router/Peer)

**Relay Image:**
```yaml
imageName: hole-punch-relay-linux
imageType: relay
imagePrefix: hole-punch-relay-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/hole-punch/impls/linux/relay
  dockerfile: Dockerfile
```

**Router Image:**
```yaml
imageName: hole-punch-router-linux
imageType: router
imagePrefix: hole-punch-router-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/hole-punch/impls/linux/router
  dockerfile: Dockerfile
```

**Peer Image:**
```yaml
imageName: hole-punch-peer-linux
imageType: peer
imagePrefix: hole-punch-peer-
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: /srv/test-plans/hole-punch/impls/linux/peer
  dockerfile: Dockerfile
```

**Note:** All three use the same YAML structure, only `imageType` and `imagePrefix` differ!

---

## Field Reference

### `imageName`
- **Type:** String
- **Required:** Yes
- **Description:** Full Docker image name including prefix
- **Examples:**
  - `transport-interop-rust-v0.56`
  - `perf-go-v0.45`
  - `hole-punch-relay-linux`

### `imageType`
- **Type:** String enum
- **Required:** Yes
- **Values:** `peer`, `relay`, `router`
- **Description:** Type of image being built
- **Usage:** Mostly informational, used in error messages

### `imagePrefix`
- **Type:** String
- **Required:** Yes
- **Description:** Prefix used when resolving base images (browser type)
- **Examples:**
  - `transport-interop-`
  - `perf-`
  - `hole-punch-peer-`

### `sourceType`
- **Type:** String enum
- **Required:** Yes
- **Values:** `github`, `local`, `browser`
- **Description:** Determines build method and required sub-fields

### `buildLocation`
- **Type:** String enum
- **Required:** Yes
- **Values:** `local`, `remote`
- **Description:** Where to execute the build
- **Note:** `remote` requires `remote` section

### `cacheDir`
- **Type:** String (path)
- **Required:** Yes
- **Description:** Absolute path to cache directory for snapshots
- **Default:** `/srv/cache`

### `forceRebuild`
- **Type:** Boolean
- **Required:** Yes
- **Description:** If true, rebuild even if image exists
- **Values:** `true`, `false`

### `outputStyle`
- **Type:** String enum
- **Required:** Yes
- **Values:** `clean`, `indented`, `filtered`
- **Description:** How to format docker build output
- **Recommended:** `clean` (transport aesthetic)

---

## Usage

### Manual Build
```bash
# Create YAML file
cat > /tmp/build-rust.yaml <<EOF
imageName: test-rust-v0.56
sourceType: local
local:
  path: /srv/test-plans/perf/impls/rust/v0.56
  dockerfile: Dockerfile
EOF

# Build
./lib/build-single-image.sh /tmp/build-rust.yaml
```

### Automated Build (via orchestrator)
```bash
# Transport
./transport/lib/build-images.sh "rust-v0.56" "false"

# Perf
./perf/lib/build-images.sh "go-v0.45|rust-v0.56" "false"

# Hole-punch
./hole-punch/lib/build-images.sh "" "" "linux" "false"
```

The orchestrator creates YAML files automatically.

---

## Advanced Use Cases

### Multi-Platform Builds (Future)
```yaml
platforms:
  - linux/amd64
  - linux/arm64
```

### Custom Build Arguments (Future)
```yaml
buildArgs:
  - NODE_VERSION=20
  - RUST_VERSION=1.75
  - ENABLE_METRICS=true
```

### Custom Registry (Future)
```yaml
registry: ghcr.io/libp2p/test-images
push: true
```

---

## See Also

- `/srv/test-plans/docs/TROUBLESHOOTING.md` - Common issues
- `/srv/test-plans/docs/MIGRATION_GUIDE.md` - Adding new test suites
