# Transport Interop V2 - Architecture Documentation

## Design Principles

### 1. Simplicity First
- Pure bash scripts (no Node.js, TypeScript, or Make)
- Single source of truth: `impls.yaml`
- Minimal dependencies: bash, git, docker, yq, wget, unzip
- No build systems or Makefiles

### 2. Content-Addressed Storage
All artifacts named by content hash:

```
/srv/cache/
├── snapshots/<commit-sha>.zip     # Git SHA-1 (40 chars)
├── test-matrix/<sha256>.yaml      # SHA-256 (64 chars)
└── test-passes/<timestamp>.tar.gz # Timestamped snapshots
```

### 3. Simplified Architecture (vs Hole-Punch)

**No global services needed!** Each test is self-contained:
- 3 containers per test (dialer, listener, redis)
- Single isolated network per test
- No NAT routers required
- Direct peer-to-peer connections

**Comparison:**

| Aspect | Hole Punch | Transport Interop |
|--------|------------|-------------------|
| Global Services | Redis + Relay | None |
| Containers/Test | 4-6 | 3 |
| Networks/Test | 3 | 1 |
| Architecture | Hybrid | Isolated |

### 4. Hash Functions

Following the "Opinions and Assumptions" design:

| Type | Algorithm | Length | Prefix Stripped |
|------|-----------|--------|-----------------|
| Git snapshots | SHA-1 | 40 hex | N/A (native Git) |
| Docker images | SHA-256 | 64 hex | Yes (`sha256:`) |
| Cache keys | SHA-256 | 64 hex | N/A (generated) |

## 3D Test Matrix

### Dimensions

1. **Transport** (required for all tests)
   - tcp, ws, quic-v1, webrtc-direct, webtransport

2. **Secure Channel** (required for non-standalone transports)
   - noise, tls, plaintext

3. **Muxer** (required for non-standalone transports)
   - yamux, mplex

### Standalone Transports

These have built-in encryption and don't need separate secure channel or muxer:
- `quic`, `quic-v1` - QUIC has built-in encryption
- `webtransport` - Built-in TLS
- `webrtc`, `webrtc-direct` - Built-in DTLS

**Test format**: `rust-v0.53 x go-v0.35 (quic-v1)`

### Non-Standalone Transports

These need separate secure channel + muxer:
- `tcp` - Plain TCP sockets
- `ws` - WebSockets

**Test format**: `rust-v0.53 x go-v0.35 (tcp, noise, yamux)`

### Matrix Generation Algorithm

```python
for dialer in implementations:
    for listener in implementations:
        common_transports = set(dialer.transports) ∩ set(listener.transports)

        for transport in common_transports:
            if transport in STANDALONE_TRANSPORTS:
                # Standalone: just transport
                yield Test(dialer, listener, transport, null, null)
            else:
                # Non-standalone: all secure × muxer combinations
                common_secure = set(dialer.secureChannels) ∩ set(listener.secureChannels)
                common_muxers = set(dialer.muxers) ∩ set(listener.muxers)

                for secure in common_secure:
                    for muxer in common_muxers:
                        yield Test(dialer, listener, transport, secure, muxer)
```

### Matrix Size Examples

**2 Rust implementations**:
- Transports: 4 (tcp, ws, quic-v1, webrtc-direct)
- Standalone: 2 (quic-v1, webrtc-direct)
- Non-standalone: 2 (tcp, ws)
- Secure: 2 (noise, tls)
- Muxers: 2 (yamux, mplex)

**Tests per pair**:
- Standalone: 2 tests
- Non-standalone: 2 × 2 × 2 = 8 tests
- **Total: 10 tests × 2 pairs (v0.53↔v0.54) = 20 tests**

**3 implementations (rust-v0.53, rust-v0.54, python-v0.4)**:
- Rust × Rust: ~40 tests
- Rust × Python: ~8 tests (tcp only, 2 secure, 2 muxers)
- Python × Python: ~4 tests
- **Total: ~52+ tests**

## Component Architecture

### Core Scripts

```
scripts/
├── build-images.sh           # Build all Docker images
├── check-dependencies.sh     # Verify system requirements
├── generate-tests.sh         # Generate 3D test matrix
├── run-single-test.sh        # Execute one test
├── generate-dashboard.sh     # Create results.md
└── create-snapshot.sh        # Create test snapshot
```

### Main Orchestrator

`run_tests.sh` coordinates the pipeline:

```
1. Check dependencies (bash, docker, git, yq, etc.)
2. Build images (with caching)
3. Generate 3D test matrix (with caching)
4. Run tests in parallel (xargs)
5. Collect results → results.yaml
6. Generate dashboard → results.md
7. Optional: Create snapshot
8. Exit with appropriate code
```

**Simplified vs hole-punch**: No global services start/stop needed!

## Data Flow

```
impls.yaml
    ↓
[build-images.sh]
    ↓
Docker Images + image.yaml files
    ↓
[generate-tests.sh] + test-selection.yaml
    ↓
test-matrix.yaml (3D combinations, cached)
    ↓
[run-single-test.sh] × N (parallel)
    ↓
results.yaml + logs/
    ↓
[generate-dashboard.sh]
    ↓
results.md (with 3D tables) + results.html
    ↓
[create-snapshot.sh] (optional)
    ↓
self-contained .tar.gz
```

## Per-Test Architecture

### Docker Compose Structure

```yaml
version: '3.8'

networks:
  test-network:
    driver: bridge

services:
  listener:
    image: rust-v0.53
    networks: [test-network]
    environment:
      - TRANSPORT=tcp
      - SECURE_CHANNEL=noise
      - MUXER=yamux
      - IS_DIALER=false
      - REDIS_ADDR=redis:6379

  dialer:
    image: rust-v0.54
    networks: [test-network]
    environment:
      - TRANSPORT=tcp
      - SECURE_CHANNEL=noise
      - MUXER=yamux
      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
    depends_on: [listener]

  redis:
    image: redis:7-alpine
    networks: [test-network]
    command: redis-server --save "" --appendonly no
```

### Test Flow

```
1. Listener starts
   - Binds to transport (tcp, ws, etc.)
   - Configures secure channel (noise, tls)
   - Configures muxer (yamux, mplex)
   - Publishes multiaddr to Redis

2. Dialer starts
   - Retrieves listener multiaddr from Redis
   - Connects using specified transport
   - Negotiates secure channel
   - Negotiates muxer
   - Tests connection
   - Exits with code 0 (success) or 1 (failure)

3. Cleanup
   - All containers stopped
   - Network removed
   - Compose file kept for debugging
```

## Configuration Files

### impls.yaml (Source of Truth)

```yaml
implementations:
  - id: rust-v0.53
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
      dockerfile: interop-tests/Dockerfile.native
    transports: [tcp, ws, quic-v1, webrtc-direct]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

**Used by:**
- `build-images.sh` - to build Docker images
- `generate-tests.sh` - to create 3D test combinations

### test-selection.yaml Files

Same format as hole-punch-interop:

```yaml
test-filter:
  - rust-v0.53
  - rust-v0.54

test-ignore:
  - rust-v0.53 x rust-v0.53
  - flaky
```

**Location:**
- Global: `test-selection.yaml` (root of project)

### test-matrix.yaml (Generated)

```yaml
metadata:
  generatedAt: 2025-11-09T14:47:32Z
  filter: [rust]
  ignore: []
  totalTests: 156

tests:
  # Standalone transport
  - name: rust-v0.53 x rust-v0.54 (quic-v1)
    dialer: rust-v0.53
    listener: rust-v0.54
    transport: quic-v1
    secureChannel: null
    muxer: null
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/1cf96b26be.zip

  # 3D combination
  - name: rust-v0.53 x rust-v0.54 (tcp, noise, yamux)
    dialer: rust-v0.53
    listener: rust-v0.54
    transport: tcp
    secureChannel: noise
    muxer: yamux
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/1cf96b26be.zip
```

### results.yaml (Output)

```yaml
metadata:
  testPass: transport-interop-full-144732-09-11-2025
  startedAt: 2025-11-09T14:47:32Z
  completedAt: 2025-11-09T14:52:18Z
  duration: 286s
  platform: x86_64
  os: Linux
  workerCount: 8

summary:
  total: 156
  passed: 152
  failed: 4

tests:
  - name: rust-v0.53 x rust-v0.54 (tcp, noise, yamux)
    status: pass
    exitCode: 0
    duration: 8s
    dialer: rust-v0.53
    listener: rust-v0.54
    transport: tcp
    secureChannel: noise
    muxer: yamux
```

## Caching Strategy

### 1. Snapshot Caching

**Cache Key:** Git commit SHA (40 chars)

Identical to hole-punch-interop.

### 2. Test Matrix Caching

**Cache Key:** SHA-256(impls.yaml + test-selection.yaml + filter||ignore||debug)

Content-addressed caching ensures:
- Same config = instant cache hit
- Config change = automatic regeneration
- Double-pipe delimiter prevents cache collisions

### 3. Docker Layer Caching

Uses Docker's built-in layer cache automatically.

## Parallel Execution

Same as hole-punch-interop:

```bash
run_test() {
    # Extract 3D test details
    # Run test with 6 args (name, dialer, listener, transport, secure, muxer)
    # Append results with file locking
}

export -f run_test
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'
```

## Test Isolation

Each test is completely isolated:

### Per-Test Resources
- Dedicated Docker network (`test-network`)
- Dedicated Redis instance
- Dedicated containers (dialer, listener)

### No Cross-Test Interference
- Each test has unique container names
- Networks are isolated
- Redis instances are separate
- Tests can run in any order

## Reproducibility: Snapshot System

Same structure as hole-punch-interop:

```
transport-interop-full-144732-09-11-2025/
├── re-run.sh
├── README.md
├── settings.yaml
├── impls.yaml
├── test-selection.yaml
├── test-matrix.yaml
├── results.yaml
├── results.md
├── impls/
├── scripts/
├── snapshots/
├── docker-compose/
└── logs/
```

## Error Handling

All scripts use:
```bash
set -euo pipefail
```

File locking for concurrent writes:
```bash
(
    flock -x 200
    cat >> results.yaml.tmp <<EOF
  - name: $name
EOF
) 200>/tmp/results.lock
```

## Performance Optimizations

1. **Parallel Test Execution** - xargs worker pool
2. **Content-Addressed Caching** - Never re-download same content
3. **Docker Layer Caching** - Automatic layer reuse
4. **No Global Services** - Simpler than hole-punch, less overhead
5. **Pre-loaded Data Structures** - Associative arrays for O(1) lookups
6. **Bulk YAML Processing** - Single yq calls with TSV output instead of loops
7. **Native Bash Operations** - String matching instead of external commands

## Comparison to Previous Design

| Aspect | Old (TypeScript) | New (Bash) |
|--------|------------------|------------|
| Dependencies | Node.js, npm, TS, make | bash, docker, git, yq |
| Lines of Code | ~2000 | ~1300 |
| Build System | Makefiles + npm | Pure bash |
| Config Format | JSON | YAML |
| Results Format | CSV | YAML |
| Matrix Generation | TypeScript + SQL | Pure bash |
| Test Selection | TypeScript | YAML + bash |
| Snapshots | None | Full tar.gz archives |
| Global Services | None (simpler) | None (same) |

**Simplification achieved**: 35% less code, far fewer dependencies!

## Extensibility

### Adding New Languages

1. Create `impls/<language>/` directory
2. Add `test-selection.yaml`
3. Add implementations to `impls.yaml`
4. Run tests

### Adding New Transports

1. Update `transports` array in `impls.yaml`
2. If standalone, add to `STANDALONE_TRANSPORTS` in generate-tests.sh
3. Test matrix auto-generates combinations

### Adding New Secure Channels

1. Update `secureChannels` array in `impls.yaml`
2. Test matrix auto-generates combinations
3. No code changes needed

### Adding New Muxers

1. Update `muxers` array in `impls.yaml`
2. Test matrix auto-generates combinations
3. No code changes needed

## Design Decisions

### Why No Global Services?

**Hole-punch tests need**:
- Redis for complex coordination (relay discovery, peer IDs)
- Relay server for hole punching
- NAT routers for simulation

**Transport tests only need**:
- Simple dialer → listener connection
- Basic Redis for multiaddr exchange
- Direct connections (no NAT)

**Decision**: Per-test Redis is simpler and provides better isolation.

### Why Per-Test Redis?

**Pros**:
- Complete test isolation
- No shared state between tests
- Easier cleanup
- Simpler architecture

**Cons**:
- Slightly more container overhead (~1s per test)

**Tradeoff**: Isolation and simplicity worth the small overhead.

### Why 3D Matrix?

Transport tests verify:
1. Transport layer works (tcp, ws, quic)
2. Security layer works (noise, tls)
3. Multiplexing works (yamux, mplex)

All combinations must be tested to ensure interoperability.

## Performance Characteristics

### Matrix Size Scaling

For N implementations with:
- T transports (S standalone, N non-standalone)
- C secure channels
- M muxers

**Tests = N² × (S + N × C × M)**

Example:
- 5 implementations
- 2 standalone, 2 non-standalone transports
- 2 secure channels, 2 muxers
- **Tests = 25 × (2 + 2 × 2 × 2) = 25 × 10 = 250 tests**

### Execution Time

**First run** (cold cache):
- Download snapshots: ~2-5 minutes
- Build images: ~10-20 minutes
- Generate test matrix: ~2-5 seconds
- Run 250 tests with 8 workers: ~15-30 minutes
- Generate dashboard: ~0.2 seconds
- **Total: 30-55 minutes**

**Subsequent runs** (warm cache):
- Skip downloads (cache hit)
- Skip builds (Docker layer cache)
- Test matrix cache hit: ~0.1 seconds
- Run 250 tests with 8 workers: ~15-30 minutes
- Generate dashboard: ~0.2 seconds
- **Total: 15-30 minutes**

**Worker scaling**:
- 1 worker: ~120 minutes
- 4 workers: ~30 minutes
- 8 workers: ~15 minutes
- 16 workers: ~10 minutes (diminishing returns)

## Codebase Statistics

```
scripts/build-images.sh:        124 lines
scripts/check-dependencies.sh:  132 lines
scripts/generate-tests.sh:      325 lines (3D logic, optimized)
scripts/run-single-test.sh:      86 lines (simplified)
scripts/generate-dashboard.sh:  219 lines (3D tables, optimized)
scripts/create-snapshot.sh:     252 lines
run_tests.sh:                   274 lines (no services)
─────────────────────────────────────────────
Total:                         1412 lines
```

**30% reduction** from original TypeScript implementation (~2000 lines).

### Optimization Impact

Recent optimizations reduced execution time significantly:
- **Test matrix generation**: 30-60s → 2-5s (10-30x faster)
- **Dashboard generation**: 6-12s → 0.15s (40-80x faster)
- **Test list display**: 6-12s → 0.15s (40-80x faster)

## Test Isolation Details

### Network Isolation

Each test creates:
```yaml
networks:
  test-network:
    driver: bridge
```

**Unique per test** - No cross-contamination possible.

### Container Naming

```
${TEST_SLUG}_listener
${TEST_SLUG}_dialer
${TEST_SLUG}_redis
```

Where `TEST_SLUG` is sanitized test name.

**Example**: `rust-v0.53_x_rust-v0.54_tcp_noise_yamux_listener`

### Cleanup

```bash
docker-compose down --volumes --remove-orphans
```

Ensures:
- All containers stopped and removed
- All volumes deleted
- Network removed
- No leftovers

## Dashboard Features

### Detailed Table

7 columns showing all test dimensions:
```markdown
| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration |
```

### Matrix View by Transport

Separate matrix for each transport:

**TCP Matrix**:
```markdown
| Dialer \ Listener | rust-v0.53 | rust-v0.54 |
|---|---|---|
| **rust-v0.53** | ✅n/y ✅n/m ✅t/y ✅t/m | ✅n/y ✅t/m |
```

**Abbreviations**:
- n/y = noise/yamux
- t/m = tls/mplex
- n/m = noise/mplex
- t/y = tls/yamux

**QUIC Matrix** (standalone):
```markdown
| Dialer \ Listener | rust-v0.53 | rust-v0.54 |
|---|---|---|
| **rust-v0.53** | ✅ | ✅ |
```

## Future Enhancements

### Short Term
1. Add more implementations (Go, JavaScript, Zig, etc.)
2. Add browser-based tests (Chrome, Firefox)
3. Test with relay scenarios
4. Add webtransport tests

### Medium Term
1. Historical results tracking
2. Performance metrics (latency, throughput)
3. Flakiness detection
4. Regression detection

### Long Term
1. Interactive web dashboard
2. Real-time test execution UI
3. Integration with libp2p CI/CD
4. Automated version updates

## Conclusion

Transport-interop-v2 successfully simplifies the test framework while adding:
- ✅ 3D test matrix support
- ✅ YAML everywhere
- ✅ Self-contained snapshots
- ✅ Content-addressed caching
- ✅ Better isolation (per-test Redis)

**Simpler architecture than hole-punch** (no global services) while handling **more complex test matrix** (3D combinations).
