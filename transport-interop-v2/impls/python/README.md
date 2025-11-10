# Python Implementations

This directory contains Python libp2p implementations for transport interoperability testing.

## Structure

```
impls/python/
├── v0.4/               # py-libp2p v0.4 (optional custom files)
├── test-selection.yaml # Default test selection for Python
└── README.md           # This file
```

## Adding a New Version

1. Add entry to `../../impls.yaml`:
   ```yaml
   - id: python-v0.5
     source:
       type: github
       repo: libp2p/py-libp2p
       commit: <full-40-char-commit-sha>
       dockerfile: interop-tests/Dockerfile
     transports:
       - tcp
     secureChannels:
       - noise
       - plaintext
     muxers:
       - yamux
       - mplex
   ```

2. Update `test-selection.yaml` if needed

3. Run: `./run_tests.sh --test-filter "python-v0.5"`

## Current Implementations

- **python-v0.4**: Basic TCP support with noise/plaintext and yamux/mplex
