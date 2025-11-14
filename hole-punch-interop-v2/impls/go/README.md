# Go Implementations

This directory contains Go libp2p implementations for hole punch interoperability testing.

## Structure

```
impls/go/
├── v0.43/              # go-libp2p v0.43 (placeholder - not yet configured)
├── test-selection.yaml # Default test selection for Go
└── README.md           # This file
```

## Adding a New Version

1. Add entry to `../../impls.yaml`:
   ```yaml
   - id: go-v0.43
     source:
       type: github
       repo: libp2p/go-libp2p
       commit: <commit-sha>
       dockerfile: <path-to-dockerfile>
     transports:
       - tcp
       - quic
   ```

2. (Optional) Create `v0.43/` directory if custom Dockerfile needed

3. Update `test-selection.yaml` if needed

4. Run: `./run_tests.sh --cache-dir /srv/cache`

## How It Works

The `scripts/build-images.sh` script reads `impls.yaml` and builds all implementations automatically. No Makefiles needed!
