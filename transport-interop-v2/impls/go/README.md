# Go Implementations

This directory contains Go libp2p implementations for transport interoperability testing.

## Structure

```
impls/go/
├── test-selection.yaml # Default test selection for Go
└── README.md           # This file
```

## Adding a New Version

1. Add entry to `../../impls.yaml`:
   ```yaml
   - id: go-v0.35
     source:
       type: github
       repo: libp2p/go-libp2p
       commit: <full-40-char-commit-sha>
       dockerfile: interop-tests/Dockerfile
     transports:
       - tcp
       - ws
       - quic-v1
     secureChannels:
       - noise
       - tls
     muxers:
       - yamux
       - mplex
   ```

2. Update `test-selection.yaml` to add filters

3. Run: `./run_tests.sh --test-filter "go-v0.35"`

## Status

No Go implementations configured yet. This is a placeholder for future additions.
