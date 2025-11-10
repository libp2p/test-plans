# Rust Implementations

This directory contains Rust libp2p implementations for transport interoperability testing.

## Structure

```
impls/rust/
├── v0.53/              # rust-libp2p v0.53 (optional custom files)
├── v0.54/              # rust-libp2p v0.54 (optional custom files)
├── test-selection.yaml # Default test selection for Rust
└── README.md           # This file
```

## Adding a New Version

1. Add entry to `../../impls.yaml`:
   ```yaml
   - id: rust-v0.55
     source:
       type: github
       repo: libp2p/rust-libp2p
       commit: <full-40-char-commit-sha>
       dockerfile: interop-tests/Dockerfile.native
     transports:
       - tcp
       - ws
       - quic-v1
       - webrtc-direct
     secureChannels:
       - noise
       - tls
     muxers:
       - yamux
       - mplex
   ```

2. Update `test-selection.yaml` if needed

3. Run: `./run_tests.sh --test-filter "rust-v0.55"`

## How It Works

The `scripts/build-images.sh` script:
1. Reads `impls.yaml` to find all implementations
2. Downloads snapshots to `/srv/cache/snapshots/<commitSha>.zip`
3. Extracts source code
4. Runs `docker build` using the Dockerfile from the repo
5. Generates `image.yaml` with metadata

No Makefiles needed - everything is driven by `impls.yaml` and bash scripts.

## Transport Combinations

Each implementation defines:
- **transports**: tcp, ws, quic-v1, webrtc-direct, etc.
- **secureChannels**: noise, tls, plaintext
- **muxers**: yamux, mplex

Tests are generated for all valid combinations:
- Standalone transports (quic-v1, webrtc): No muxer/secure needed
- Other transports (tcp, ws): Require muxer + secureChannel

Example test: `rust-v0.53 x rust-v0.54 (tcp, noise, yamux)`
