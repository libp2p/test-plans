# images.yaml Schema Documentation

## Overview

The `images.yaml` file defines all libp2p implementations, baselines, routers, and relays to be tested. It is the primary configuration file that drives test matrix generation, Docker image building, and test execution for all three test suites (perf, transport, hole-punch).

**Location**:
- `perf/images.yaml`
- `transport/images.yaml`
- `hole-punch/images.yaml`

**Purpose**:
- Define implementation capabilities (transports, secure channels, muxers)
- Specify Docker build configuration (local, GitHub, browser sources)
- Define test aliases for filtering
- Document baseline implementations (perf only)
- Configure router and relay implementations (hole-punch only)

---

## Top-Level Structure

### Common Sections (All Test Types)

```yaml
test-aliases:          # Reusable filter patterns
implementations:       # libp2p peer implementations
```

### Test-Type-Specific Sections

**Perf**:
```yaml
baselines:            # Non-libp2p baseline implementations (iperf, HTTPS, QUIC-Go)
```

**Hole-Punch**:
```yaml
routers:              # NAT router implementations
relays:               # Relay server implementations
```

---

## test-aliases Section

Defines reusable patterns for test filtering with `--test-ignore` and related flags.

### Schema

```yaml
test-aliases:
  - alias: string     # Alias name (used with ~ prefix)
    value: string     # Pipe-separated ID patterns
```

### Example

```yaml
test-aliases:
  - alias: "all"
    value: "~baselines|~images"

  - alias: "rust"
    value: "rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56"

  - alias: "go"
    value: "go-v0.38|go-v0.39|go-v0.40|go-v0.41|go-v0.42|go-v0.43|go-v0.44|go-v0.45"

  - alias: "browsers"
    value: "chromium-rust-v0.56|firefox-js-v1.x|webkit-js-v2.x"

  - alias: "failing"
    value: "js-v3.x|go-v0.45"
```

### Usage

```bash
# Select only rust implementations
./run.sh --test-ignore "!~rust"

# Ignore all browsers
./run.sh --test-ignore "~browsers"

# Select everything except failing implementations
./run.sh --test-ignore "~failing"
```

---

## implementations Section

Defines libp2p peer implementations to test.

### Required Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier (alphanumeric, dash, underscore) |
| `source` | object | Yes | Build source configuration |
| `transports` | array | Yes | Supported transport protocols |
| `secureChannels` | array | Yes | Supported secure channels (can be empty for standalone transports) |
| `muxers` | array | Yes | Supported stream multiplexers (can be empty for standalone transports) |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | `id` | Human-readable name |
| `dialOnly` | boolean | `false` | Can only dial, not listen (transport only) |

### Source Configuration

Three source types are supported:

#### Local Source

Build from local filesystem:

```yaml
source:
  type: local
  path: string              # Path to source directory (relative or absolute)
  dockerfile: string        # Dockerfile name (default: "Dockerfile")
  patchPath: string         # Optional: Directory containing patch file
  patchFile: string         # Optional: Patch filename
```

#### GitHub Source

Build from GitHub repository:

```yaml
source:
  type: github
  repo: string              # GitHub repository (org/repo)
  commit: string            # Full commit hash (40 characters)
  dockerfile: string        # Path to Dockerfile in repo
  buildContext: string      # Build context directory (default: ".")
  requiresSubmodules: bool  # Use git clone with submodules (default: false)
  patchPath: string         # Optional: Directory containing patch file
  patchFile: string         # Optional: Patch filename
```

#### Browser Source

Build browser-based implementation (transport only):

```yaml
source:
  type: browser
  baseImage: string         # Base implementation ID to wrap
  browser: string           # Browser: chromium, firefox, or webkit
  dockerfile: string        # Path to browser Dockerfile
  buildContext: string      # Build context directory
  patchPath: string         # Optional: Directory containing patch file
  patchFile: string         # Optional: Patch filename
```

### Complete Examples

#### Local Source (Perf/Hole-Punch)

```yaml
implementations:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile
    transports: [tcp, quic-v1, webrtc-direct, ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  - id: go-v0.45
    source:
      type: local
      path: images/go/v0.45
      dockerfile: Dockerfile
    transports: [tcp, quic-v1, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

#### GitHub Source (Transport)

```yaml
implementations:
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

  - id: go-v0.45
    source:
      type: github
      repo: libp2p/go-libp2p
      commit: 7d16f5445b6e52e6c4b52ff0b7c0d8e53c0e3f48
      dockerfile: test-plans/PingDockerfile
      requiresSubmodules: true
    transports: [tcp, ws, wss, quic-v1, webtransport, webrtc-direct]
    secureChannels: [tls, noise]
    muxers: [yamux]
```

#### Browser Source (Transport)

```yaml
implementations:
  # Base Node.js implementation
  - id: js-v3.x
    source:
      type: github
      repo: libp2p/js-libp2p
      commit: 5f3c0e8d9a3b4c2f1e0d9c8b7a6f5e4d3c2b1a09
      dockerfile: interop-tests/Dockerfile
    transports: [ws, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  # Browser wrapper (dialOnly)
  - id: chromium-js-v3.x
    source:
      type: browser
      baseImage: js-v3.x
      browser: chromium
      dockerfile: impls/js/v3.x/BrowserDockerfile
      buildContext: impls/js/v3.x
    dialOnly: true
    transports: [ws, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  - id: firefox-js-v3.x
    source:
      type: browser
      baseImage: js-v3.x
      browser: firefox
      dockerfile: impls/js/v3.x/BrowserDockerfile
      buildContext: impls/js/v3.x
    dialOnly: true
    transports: [ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

---

## baselines Section (Perf Only)

Defines non-libp2p baseline implementations for performance comparison.

### Schema

Same as `implementations` but stored in a separate section:

```yaml
baselines:
  - id: string
    source: object
    transports: array
    secureChannels: array
    muxers: array
```

### Example

```yaml
baselines:
  # Raw TCP performance with iperf3
  - id: iperf
    source:
      type: local
      path: images/iperf/v3.0
      dockerfile: Dockerfile
    transports: [tcp]
    secureChannels: []
    muxers: []

  # HTTPS baseline (standalone transport)
  - id: https
    source:
      type: local
      path: images/https/v1.0
      dockerfile: Dockerfile
    transports: [https]
    secureChannels: []
    muxers: []

  # QUIC-Go baseline (standalone QUIC implementation)
  - id: quic-go
    source:
      type: local
      path: images/quic-go/v1.0
      dockerfile: Dockerfile
    transports: [quic]
    secureChannels: []
    muxers: []
```

**Note**: Baseline tests are generated separately from main tests and run sequentially (WORKER_COUNT=1).

---

## routers Section (Hole-Punch Only)

Defines NAT router implementations for hole-punch tests.

### Schema

```yaml
routers:
  - id: string
    source: object
```

Routers do not have transports, secureChannels, or muxers fields as they only perform routing/NAT.

### Example

```yaml
routers:
  - id: linux
    source:
      type: local
      path: images/linux
      dockerfile: Dockerfile
```

**Note**: Docker image name will be `hole-punch-routers-<id>` (e.g., `hole-punch-routers-linux`).

---

## relays Section (Hole-Punch Only)

Defines relay server implementations for DCUtR protocol.

### Schema

```yaml
relays:
  - id: string
    source: object
    transports: array
    secureChannels: array
    muxers: array
```

Same fields as implementations since relays are libp2p nodes.

### Example

```yaml
relays:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile.relay
    transports: [tcp, quic-v1, webrtc-direct, ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

**Note**: Docker image name will be `hole-punch-relays-<id>` (e.g., `hole-punch-relays-rust-v0.56`).

---

## Transport Names

### Common Transports

Standard libp2p transports:

| Transport | Type | Requires Secure/Muxer |
|-----------|------|----------------------|
| `tcp` | Non-standalone | Yes |
| `ws` | Non-standalone | Yes |
| `wss` | Non-standalone | Yes (WebSocket Secure) |
| `quic-v1` | Standalone | No |
| `webtransport` | Standalone | No |
| `webrtc-direct` | Standalone | No |

### Baseline-Only Transports (Perf)

| Transport | Description |
|-----------|-------------|
| `https` | HTTPS baseline |
| `quic` | QUIC-Go baseline |

**Standalone transports** have built-in security and multiplexing, so tests using them have `secureChannel: null` and `muxer: null`.

---

## Secure Channel Names

Standard libp2p secure channels:

| Name | Description |
|------|-------------|
| `noise` | Noise Protocol Framework |
| `tls` | TLS 1.3 |

Used only with non-standalone transports (tcp, ws, wss).

---

## Muxer Names

Standard libp2p stream multiplexers:

| Name | Description |
|------|-------------|
| `yamux` | Yet Another Multiplexer |
| `mplex` | Multiplex |

Used only with non-standalone transports (tcp, ws, wss).

---

## Complete Examples by Test Type

### Perf images.yaml

```yaml
test-aliases:
  - alias: "all"
    value: "~baselines|~images"
  - alias: "images"
    value: "dotnet-v1.0|go-v0.45|js-v3.x|rust-v0.56"
  - alias: "baselines"
    value: "https|quic-go|iperf"
  - alias: "rust"
    value: "rust-v0.56"
  - alias: "go"
    value: "go-v0.45"

baselines:
  - id: iperf
    source:
      type: local
      path: images/iperf/v3.0
      dockerfile: Dockerfile
    transports: [tcp]
    secureChannels: []
    muxers: []

  - id: https
    source:
      type: local
      path: images/https/v1.0
      dockerfile: Dockerfile
    transports: [https]
    secureChannels: []
    muxers: []

implementations:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile
    transports: [tcp, quic-v1, webrtc-direct, ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  - id: go-v0.45
    source:
      type: local
      path: images/go/v0.45
      dockerfile: Dockerfile
    transports: [tcp, quic-v1, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

### Transport images.yaml

```yaml
test-aliases:
  - alias: "all"
    value: "~browsers|~rust|~go|~js"
  - alias: "browsers"
    value: "chromium-rust-v0.56|firefox-js-v1.x|webkit-js-v2.x"
  - alias: "rust"
    value: "rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56"
  - alias: "go"
    value: "go-v0.38|go-v0.39|go-v0.40|go-v0.41|go-v0.42|go-v0.43|go-v0.44|go-v0.45"
  - alias: "js"
    value: "js-v1.x|js-v2.x|js-v3.x"

implementations:
  # Native implementations
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

  - id: go-v0.45
    source:
      type: github
      repo: libp2p/go-libp2p
      commit: 7d16f5445b6e52e6c4b52ff0b7c0d8e53c0e3f48
      dockerfile: test-plans/PingDockerfile
    transports: [tcp, ws, wss, quic-v1, webtransport, webrtc-direct]
    secureChannels: [tls, noise]
    muxers: [yamux]

  # Base browser implementation
  - id: js-v3.x
    source:
      type: github
      repo: libp2p/js-libp2p
      commit: 5f3c0e8d9a3b4c2f1e0d9c8b7a6f5e4d3c2b1a09
      dockerfile: interop-tests/Dockerfile
    transports: [ws, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  # Browser wrappers (dialOnly)
  - id: chromium-js-v3.x
    source:
      type: browser
      baseImage: js-v3.x
      browser: chromium
      dockerfile: impls/js/v3.x/BrowserDockerfile
      buildContext: impls/js/v3.x
    dialOnly: true
    transports: [ws, webtransport]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  - id: firefox-js-v3.x
    source:
      type: browser
      baseImage: js-v3.x
      browser: firefox
      dockerfile: impls/js/v3.x/BrowserDockerfile
      buildContext: impls/js/v3.x
    dialOnly: true
    transports: [ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

### Hole-Punch images.yaml

```yaml
test-aliases:
  - alias: "failing"
    value: ""

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
    transports: [tcp, quic-v1, webrtc-direct, ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

implementations:
  - id: rust-v0.56
    source:
      type: local
      path: images/rust/v0.56
      dockerfile: Dockerfile.peer
    transports: [tcp, quic-v1, webrtc-direct, ws]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

---

## Field Validation Rules

### ID Format

- Must be unique within section
- Alphanumeric, dash, underscore only
- No spaces or special characters
- Convention: `<language>-v<version>` (e.g., `rust-v0.56`)
- Browser IDs: `<browser>-<base-id>` (e.g., `chromium-js-v3.x`)

### Transport Arrays

- At least one transport required
- Can mix standalone and non-standalone transports
- Common transports enable cross-implementation testing

### Secure Channel / Muxer Arrays

- Can be empty for implementations with only standalone transports
- Required if any non-standalone transports are specified
- At least one of each required for non-standalone transport tests

### Source Type Constraints

- **Local**: `path` must exist, `dockerfile` must be in path
- **GitHub**: `commit` must be 40-character SHA-1 hash, `repo` must be valid
- **Browser**: `baseImage` must reference existing implementation ID

### Patch File Constraints

- `patchPath` and `patchFile` must both be specified together
- `patchFile` cannot contain path separators (`/` or `\`)
- Patch file must exist in `patchPath` directory
- Patch must be in unified diff format

---

## Usage in Test Framework

### Test Matrix Generation

The generate-tests.sh script:

1. Loads images.yaml
2. Expands test-aliases for filtering
3. Generates all valid permutations:
   - **Perf**: baselines, implementations
   - **Transport**: implementations (including browsers)
   - **Hole-Punch**: implementations × relays × routers
4. Filters based on command-line arguments
5. Outputs test-matrix.yaml

### Docker Image Building

The build system:

1. Reads source configuration from images.yaml
2. Generates docker-build-*.yaml for each implementation
3. Builds images using appropriate strategy:
   - Local: `docker build` from filesystem
   - GitHub: Download snapshot or clone with submodules
   - Browser: Tag base image and build browser wrapper
4. Applies patches if specified
5. Tags images as `<test-type>-<section>-<id>`

### Filter Application

Command-line filters reference IDs and aliases:

```bash
# By ID
./run.sh --test-ignore "rust-v0.53"

# By alias
./run.sh --test-ignore "~browsers"

# Negation (select only)
./run.sh --test-ignore "!rust-v0.56"

# Combination
./run.sh --test-ignore "~browsers|rust-v0.53"
```

---

## Related Files

- **Test Matrix Generation**: `perf/lib/generate-tests.sh`, `transport/lib/generate-tests.sh`, `hole-punch/lib/generate-tests.sh`
- **Docker Building**: `lib/lib-image-building.sh`, `lib/build-single-image.sh`
- **Filter Engine**: `lib/lib-filter-engine.sh`
- **Image Utilities**: `lib/lib-test-images.sh`
- **Output**: `test-matrix.yaml`, `docker-build-*.yaml`

---

## See Also

- **[docs/test-matrix-schema.md](test-matrix-schema.md)** - test-matrix.yaml schema specification
- **[docs/docker-build-schema.md](docker-build-schema.md)** - docker-build-*.yaml schema specification
- **[docs/inputs-schema.md](inputs-schema.md)** - inputs.yaml schema specification
- **[docs/overall-flow.md](overall-flow.md)** - Test execution flow overview
