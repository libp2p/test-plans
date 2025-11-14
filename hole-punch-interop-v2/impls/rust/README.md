# Rust Implementations

This directory contains Rust libp2p implementations for hole punch interoperability testing.

## Structure

```
impls/rust/
├── v0.53/              # rust-libp2p v0.53 (optional custom Dockerfile)
├── test-selection.yaml # Default test selection for Rust
└── README.md           # This file
```

## Adding a New Version

1. Add entry to `../../impls.yaml`:
   ```yaml
   - id: rust-v0.54
     source:
       type: github
       repo: libp2p/rust-libp2p
       commit: <new-commit-sha>
       dockerfile: hole-punching-tests/Dockerfile
     transports:
       - tcp
       - quic
   ```

2. (Optional) Create `v0.54/` directory if custom Dockerfile needed

3. Update `test-selection.yaml` if needed to filter/ignore new version

4. Run: `./run_tests.sh --cache-dir /srv/cache`

## How It Works

The `scripts/build-images.sh` script:
1. Reads `impls.yaml` to find all implementations
2. Downloads snapshots to `/srv/cache/snapshots/<commitSha>.zip`
3. Extracts source code
4. Runs `docker build` using the Dockerfile from the repo
5. Generates `image.yaml` with metadata

No Makefiles needed - everything is driven by `impls.yaml` and bash scripts.
