# Hole Punch Interoperability Tests v2

Simplified, pure-bash implementation of hole punching interoperability tests for libp2p.

## Architecture

This test suite uses:
- **Pure bash** orchestration (no Node.js/npm)
- **YAML** for all configuration and data files
- **Content-addressed caching** under `/srv/cache/`
- **Hybrid architecture**: Global Redis/Relay services + per-test containers
- **Self-contained snapshots** for reproducibility

## Quick Start

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install docker.io git wget unzip

# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Run tests
./run_tests.sh --cache-dir /srv/cache --workers 4
```

## Directory Structure

```
hole-punch-interop-v2/
├── impls/                     # Implementation directories
│   ├── rust/
│   │   ├── v0.53/            # Contains Dockerfile (if custom build needed)
│   │   ├── test-selection.yaml
│   │   └── README.md
│   └── go/
│       ├── test-selection.yaml
│       └── README.md
├── scripts/                   # Bash scripts
│   ├── build-images.sh       # Reads impls.yaml, builds all images
│   ├── generate-tests.sh
│   ├── start-global-services.sh
│   ├── stop-global-services.sh
│   ├── run-single-test.sh
│   ├── create-snapshot.sh
│   └── generate-dashboard.sh
├── impls.yaml                 # Implementation definitions (source of truth)
├── test-selection.yaml        # Default test selection
├── run_tests.sh              # Main orchestrator
└── README.md                  # This file
```

## Configuration Files

### impls.yaml
Defines all implementations to test with their source repositories and supported transports.

### test-selection.yaml
Default test filters and ignore patterns for full test passes.

### impls/\<lang\>/test-selection.yaml
Per-language defaults used when testing specific implementations.

## Test Selection

Test selection uses pipe-separated substring matching:
- `--test-filter "rust-v0.53|go-v0.43"` - Select tests matching either pattern
- `--test-ignore "tcp"` - Exclude tests containing "tcp"

If no CLI args provided, defaults from `test-selection.yaml` files are used.

## Content-Addressed Caching

All artifacts cached under `/srv/cache/`:
- `snapshots/<commitSha>.zip` - GitHub repository snapshots (git SHA-1)
- `test-matrix/<sha256>.yaml` - Test matrices
- `docker-compose/<sha256>.yaml` - Docker compose files
- `test-passes/hole-punch-<kind>-<timestamp>.zip` - Complete test snapshots

## Hash Functions

- **Git snapshots**: SHA-1 (40 hex chars, from Git)
- **Docker images**: SHA-256 (64 hex chars, `sha256:` prefix stripped)
- **Content cache**: SHA-256 (64 hex chars)

All hash algorithm prefixes are omitted from identifiers for simplicity.

## Dependencies

- bash 4.0+
- git 2.0+
- docker 20.10+
- yq 4.0+
- wget, unzip

**Note:** No Node.js, npm, or make required!

## Documentation

See `simplification-plan.md` and `caching-architecture.md` in the parent `hole-punch-interop/` directory for complete design documentation.
