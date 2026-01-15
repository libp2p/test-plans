# Overall Test Execution Flow

## Overview

This document describes the common execution flow shared by all three test suites (perf, transport, hole-punch) and explains what YAML files are generated at each stage, how they're used, and where they're stored.

All three test runners (`perf/run.sh`, `transport/run.sh`, `hole-punch/run.sh`) follow the same basic structure with test-type-specific variations.

---

## High-Level Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. BOOTSTRAP                                                    │
│    • Load inputs.yaml (if exists)                               │
│    • Set SCRIPT_LIB_DIR, TEST_ROOT                              │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. INITIALIZATION                                               │
│    • Source common libraries                                    │
│    • Parse command-line arguments                               │
│    • Set test-specific defaults                                 │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. EARLY EXIT OPTIONS (if requested)                            │
│    • --list-images: Display implementations and exit            │
│    • --list-tests: Generate matrix, display tests, exit         │
│    • --check-deps: Check dependencies and exit                  │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. INITIALIZE TEST RUN                                          │
│    • Compute TEST_RUN_KEY from config hash                      │
│    • Create TEST_PASS_DIR                                       │
│    • Create folder structure (logs/, results/, etc.)            │
│    GENERATES: inputs.yaml ──────────────────────────────────────┤
│    • Check dependencies                                         │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 5. GENERATE TEST MATRIX                                         │
│    • Call generate-tests.sh                                     │
│    • Load images.yaml                                           │
│    • Expand filters with aliases                                │
│    • Check cache for existing matrix                            │
│    • Generate test permutations                                 │
│    GENERATES: test-matrix.yaml ─────────────────────────────────┤
│    COPIES: images.yaml to TEST_PASS_DIR                         │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. PRINT TEST SELECTION                                         │
│    • Display selected and ignored tests                         │
│    • Calculate required Docker images                           │
│    • Prompt for confirmation (unless --yes)                     │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 7. BUILD DOCKER IMAGES                                          │
│    • For each required implementation:                          │
│      - Check if image exists                                    │
│      GENERATES: docker-build-*.yaml ────────────────────────────┤
│      - Build image (local/GitHub/browser)                       │
│      - Apply patches if specified                               │
│      - Tag as <test-type>-<section>-<id>                        │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 8. RUN TESTS                                                    │
│    • Start global services (Redis)                              │
│    • For each test in test-matrix.yaml:                         │
│      - Generate docker-compose.yaml                             │
│      - Start containers                                         │
│      - Wait for dialer to exit                                  │
│      - Extract results from dialer logs                         │
│      - Write to results.yaml.tmp                                │
│      GENERATES: results/<test-name>.yaml (per test) ────────────┤
│      - Cleanup containers                                       │
│    • Stop global services                                       │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 9. COLLECT RESULTS                                              │
│    • Count pass/fail from temporary files                       │
│    • Generate final results with metadata                       │
│    GENERATES: results.yaml ─────────────────────────────────────┤
│    • Display summary and failed tests                           │
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 10. GENERATE DASHBOARD                                          │
│    • Generate HTML dashboard from results                       │
│    • Generate charts/plots (perf only)                          │
│    GENERATES: results.html, charts.html (perf) ─────────────────┤
└────────────────────────────────┬────────────────────────────────┘
                                 ▼                                
┌─────────────────────────────────────────────────────────────────┐
│ 11. CREATE SNAPSHOT (if --snapshot)                             │
│    • Modify inputs.yaml for snapshot context                    │
│    • Package test pass directory                                │
│    • Create ZIP archive                                         │
│    GENERATES: <test-pass-name>.zip ─────────────────────────────┤
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Phase Breakdown

### Phase 1: Bootstrap (Lines ~23-71)

**Purpose**: Load configuration before libraries are sourced

**Key Actions**:
1. Check if `inputs.yaml` exists in current directory
2. If exists, load environment variables and command-line args
3. Merge with current CLI args (CLI takes precedence)
4. Set `SCRIPT_LIB_DIR` and `TEST_ROOT`

**YAML Files Used**:
- **INPUT**: `inputs.yaml` (if exists in current directory)

**Code Location**:
- `perf/run.sh:30-71`
- `transport/run.sh:30-71`
- `hole-punch/run.sh:30-71`

**Why Bootstrap First**:
The `inputs.yaml` file must be loaded *before* libraries are sourced because it sets `SCRIPT_LIB_DIR` which is needed to find the libraries.

---

### Phase 2: Initialization (Lines ~88-207)

**Purpose**: Set up test environment and parse configuration

**Key Actions**:
1. Source common libraries from `$SCRIPT_LIB_DIR`:
   - `lib-common-init.sh` - Common variable initialization
   - `lib-filter-engine.sh` - Alias expansion and filtering
   - `lib-image-building.sh` - Docker image building
   - `lib-global-services.sh` - Redis service management
   - `lib-test-execution.sh` - Test execution coordination
   - `lib-output-formatting.sh` - Terminal output formatting
   - Others as needed

2. Initialize common variables via `init_common_variables()`:
   - `IMAGES_YAML` (default: `./images.yaml`)
   - `CACHE_DIR` (default: `/srv/cache`)
   - `TEST_RUN_DIR` (default: `/srv/cache/test-run`)
   - `DEBUG` (default: `false`)
   - `WORKER_COUNT` (default: varies by test type)
   - Filter variables (TEST_IGNORE, TRANSPORT_IGNORE, etc.)

3. Parse command-line arguments:
   ```bash
   while [[ $# -gt 0 ]]; do
     case $1 in
       --test-ignore)     TEST_IGNORE="$2"; shift 2 ;;
       --transport-ignore) TRANSPORT_IGNORE="$2"; shift 2 ;;
       --debug)           DEBUG=true; shift ;;
       --yes)             AUTO_YES=true; shift ;;
       ...
     esac
   done
   ```

4. Set test-specific defaults:
   - **Perf**: `ITERATIONS=10`, `UPLOAD_BYTES=1GB`, `DOWNLOAD_BYTES=1GB`
   - **Transport**: `WORKER_COUNT=$(nproc)`
   - **Hole-Punch**: `WORKER_COUNT=$(nproc)`

**Code Location**:
- `perf/run.sh:88-207`
- `transport/run.sh:88-207`
- `hole-punch/run.sh:88-207`

---

### Phase 3: Early Exit Options (Lines ~223-351)

**Purpose**: Handle informational flags that don't require full test run

#### Option 1: `--list-images`

```bash
./run.sh --list-images
```

**Actions**:
1. Read `images.yaml` sections (implementations, baselines, routers, relays)
2. Display each implementation with its ID, transports, secure channels, muxers
3. Exit without generating any files

#### Option 2: `--list-tests`

```bash
./run.sh --test-ignore "~browsers" --list-tests
```

**Actions**:
1. Generate test matrix (same as Phase 5)
2. Display selected and ignored tests
3. Exit without building images or running tests

**YAML Files Generated**:
- `test-matrix.yaml` (if not cached)

#### Option 3: `--check-deps`

```bash
./run.sh --check-deps
```

**Actions**:
1. Check for required dependencies:
   - Docker or Podman
   - docker-compose or podman-compose
   - yq (YAML processor)
   - jq (JSON processor)
2. Display versions and status
3. Exit

**Code Location**:
- `perf/run.sh:223-351`
- `transport/run.sh:223-351`
- `hole-punch/run.sh:223-351`

---

### Phase 4: Initialize Test Run (Lines ~353-414)

**Purpose**: Create test pass directory and capture configuration

**Key Actions**:

1. **Compute TEST_RUN_KEY** (content-addressed cache key):
   ```bash
   TEST_RUN_KEY=$(compute_test_run_key \
     "$IMAGES_YAML" \
     "$TEST_IGNORE" \
     "$BASELINE_IGNORE" \
     "$TRANSPORT_IGNORE" \
     "$SECURE_IGNORE" \
     "$MUXER_IGNORE" \
     "$DEBUG")
   ```
   - Hash of images.yaml content + all filters
   - Returns 8-character hex string (e.g., `e5b6ea57`)

2. **Generate TEST_PASS_NAME**:
   ```
   Format: <test-type>-<key>-<timestamp>
   Example: perf-e5b6ea57-185931-28-12-2025
   ```

3. **Create TEST_PASS_DIR**:
   ```bash
   TEST_PASS_DIR="${TEST_RUN_DIR}/${TEST_PASS_NAME}"
   mkdir -p "${TEST_PASS_DIR}"/{logs,results,docker-compose}
   ```

   Directory structure:
   ```
   /srv/cache/test-run/perf-e5b6ea57-185931-28-12-2025/
   ├── logs/                  # Per-test log files
   ├── results/               # Per-test result files
   ├── docker-compose/        # Generated docker-compose files
   ├── inputs.yaml            # Captured configuration (generated here)
   ├── images.yaml            # Copied from source (Phase 5)
   ├── test-matrix.yaml       # Generated test matrix (Phase 5)
   └── results.yaml           # Final aggregated results (Phase 9)
   ```

4. **Generate inputs.yaml**:
   ```bash
   generate_inputs_yaml \
     "$TEST_PASS_DIR/inputs.yaml" \
     "$TEST_TYPE" \
     "${ORIGINAL_ARGS[@]}"
   ```

   Captures:
   - Test type (perf/transport/hole-punch)
   - Original command-line arguments
   - All environment variables

5. **Check dependencies** (unless already done)

**YAML Files Generated**:
- **`inputs.yaml`** - Configuration snapshot for reproducibility
  - Schema: [docs/inputs-schema.md](inputs-schema.md)
  - Location: `$TEST_PASS_DIR/inputs.yaml`

**Code Location**:
- `perf/run.sh:353-414`
- `transport/run.sh:353-414`
- `hole-punch/run.sh:353-414`

---

### Phase 5: Generate Test Matrix (Lines ~445-463)

**Purpose**: Create all test combinations from images.yaml with filtering

**Key Actions**:

1. **Call generate-tests.sh**:
   ```bash
   bash "${SCRIPT_DIR}/generate-tests.sh"
   ```

2. **Inside generate-tests.sh**:

   a. **Load and expand filters**:
   ```bash
   load_aliases  # From images.yaml test-aliases section
   EXPANDED_TEST_IGNORE=$(expand_filter_string "${TEST_IGNORE}" all_image_ids)
   ```

   Example expansion:
   ```
   Input:  "~rust"
   Output: "rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56"

   Input:  "!~rust"
   Output: "<everything except rust implementations>"
   ```

   b. **Check cache**:
   ```bash
   CACHE_FILE="${CACHE_DIR}/test-run-matrix/${TEST_TYPE}-${TEST_RUN_KEY}.yaml"
   if [ -f "$CACHE_FILE" ] && [ "$FORCE_MATRIX_REBUILD" != "true" ]; then
     cp "$CACHE_FILE" "${TEST_PASS_DIR}/test-matrix.yaml"
     exit 0  # Cache hit!
   fi
   ```

   c. **Apply filters**:
   ```bash
   filtered_image_ids=($(filter_entities "implementations"))
   filtered_transport_names=($(filter_names "transports"))
   filtered_secure_names=($(filter_names "secureChannels"))
   filtered_muxer_names=($(filter_names "muxers"))
   ```

   d. **Generate test combinations**:

   **Perf/Transport**:
   ```
   For each dialer in implementations:
     For each listener in implementations:
       For each common transport:
         If standalone transport (quic-v1, webtransport, etc.):
           Add test: "dialer x listener (transport)"
         Else:
           For each common secure channel:
             For each common muxer:
               Add test: "dialer x listener (transport, secure, muxer)"
   ```

   **Hole-Punch** (additional dimensions):
   ```
   For each relay in relays:
     For each dialer_router in routers:
       For each listener_router in routers:
         For each dialer in implementations:
           For each listener in implementations:
             For each common transport:
               [Same as above for secure/muxer]
   ```

   e. **Write test-matrix.yaml**:
   ```yaml
   metadata:
     ignore: "${TEST_IGNORE}"
     transportIgnore: "${TRANSPORT_IGNORE}"
     ...
     totalTests: ${#main_tests[@]}
     ignoredTests: ${#ignored_main_tests[@]}
     debug: ${DEBUG}

   tests:
     - id: "rust-v0.56 x rust-v0.56 (tcp, noise, yamux)"
       transport: tcp
       secureChannel: noise
       muxer: yamux
       dialer:
         id: rust-v0.56
         imageName: perf-implementations-rust-v0.56
       listener:
         id: rust-v0.56
         imageName: perf-implementations-rust-v0.56

   ignoredTests:
     [Tests filtered out but documented]
   ```

   f. **Copy images.yaml**:
   ```bash
   cp "${IMAGES_YAML}" "${TEST_PASS_DIR}/"
   ```

   g. **Cache the matrix**:
   ```bash
   save_to_cache "${TEST_PASS_DIR}/test-matrix.yaml" \
     "${TEST_RUN_KEY}" \
     "${CACHE_DIR}/test-run-matrix" \
     "${TEST_TYPE}"
   ```

**YAML Files Generated**:
- **`test-matrix.yaml`** - All test combinations to execute
  - Schema: [docs/test-matrix-schema.md](test-matrix-schema.md)
  - Primary: `$TEST_PASS_DIR/test-matrix.yaml`
  - Cached: `$CACHE_DIR/test-run-matrix/<test-type>-<key>.yaml`

**YAML Files Copied**:
- **`images.yaml`** - Implementation definitions (for reference)
  - Schema: [docs/images-yaml-schema.md](images-yaml-schema.md)
  - Copied to: `$TEST_PASS_DIR/images.yaml`

**Code Location**:
- Main: `perf/run.sh:445-463`
- Generator: `perf/lib/generate-tests.sh`

**Cache Benefits**:
- Identical configurations reuse cached matrix
- Saves ~5-10 seconds on subsequent runs
- Cache key includes all filters + images.yaml hash

---

### Phase 6: Print Test Selection (Lines ~465-533)

**Purpose**: Display what will be tested and confirm with user

**Key Actions**:

1. **Count selected and ignored tests**:
   ```bash
   SELECTED=$(yq eval '.tests | length' test-matrix.yaml)
   IGNORED=$(yq eval '.ignoredTests | length' test-matrix.yaml)
   ```

2. **Display selected tests** (sample):
   ```
   Selected Tests (20):
     ✓ rust-v0.56 x rust-v0.56 (tcp, noise, yamux)
     ✓ rust-v0.56 x rust-v0.56 (tcp, noise, mplex)
     ✓ rust-v0.56 x rust-v0.56 (quic-v1)
     ...
   ```

3. **Display ignored tests** (if any):
   ```
   Ignored Tests (156):
     ✗ go-v0.45 x go-v0.45 (tcp, noise, yamux)
     ✗ js-v3.x x js-v3.x (tcp, noise, yamux)
     ...
   ```

4. **Calculate required Docker images**:
   ```bash
   REQUIRED_IMAGES=($(yq eval '.tests[].dialer.imageName' test-matrix.yaml | sort -u))
   REQUIRED_IMAGES+=($(yq eval '.tests[].listener.imageName' test-matrix.yaml | sort -u))
   ```

5. **Prompt for confirmation** (unless `--yes`):
   ```
   Build 4 Docker images and run 20 tests? [Y/n]
   ```

**Code Location**:
- `perf/run.sh:465-533`
- `transport/run.sh:465-533`
- `hole-punch/run.sh:465-533`

---

### Phase 7: Build Docker Images (Lines ~535-561)

**Purpose**: Build all required Docker images from source

**Key Actions**:

1. **For each section** (implementations, baselines, routers, relays):
   ```bash
   build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
   ```

2. **Inside build_images_from_section**:

   a. **Read images.yaml**:
   ```bash
   count=$(yq eval ".$section | length" "${IMAGES_YAML}")
   ```

   b. **For each implementation**:
   ```bash
   for ((i=0; i<count; i++)); do
     impl_id=$(yq eval ".${section}[$i].id" "${IMAGES_YAML}")
     source_type=$(yq eval ".${section}[$i].source.type" "${IMAGES_YAML}")
   ```

   c. **Check if image exists**:
   ```bash
   image_name="${TEST_TYPE}-${section}-${impl_id}"
   if docker_image_exists "$image_name" && [ "$force_rebuild" != "true" ]; then
     print_success "$image_name (already built)"
     continue
   fi
   ```

   d. **Generate docker-build-*.yaml**:
   ```yaml
   imageName: perf-implementations-rust-v0.56
   imageType: peer
   imagePrefix: perf
   sourceType: local
   buildLocation: local
   cacheDir: /srv/cache
   forceRebuild: false

   local:
     path: images/rust/v0.56
     dockerfile: Dockerfile
     patchPath: ""
     patchFile: ""
   ```

   e. **Execute build**:
   ```bash
   bash "${SCRIPT_LIB_DIR}/build-single-image.sh" "$yaml_file"
   ```

3. **Inside build-single-image.sh**:

   a. **Load YAML parameters**:
   ```bash
   imageName=$(yq eval '.imageName' "$YAML_FILE")
   sourceType=$(yq eval '.sourceType' "$YAML_FILE")
   ```

   b. **Build based on source type**:

   **Local Source**:
   ```bash
   docker build -f "$path/$dockerfile" -t "$imageName" "$path"
   ```

   **GitHub Source** (snapshot download):
   ```bash
   wget -O snapshot.zip "https://github.com/$repo/archive/$commit.zip"
   unzip snapshot.zip
   docker build -f "$extracted/$dockerfile" -t "$imageName" "$context"
   ```

   **GitHub Source** (with submodules):
   ```bash
   git clone --depth 1 "https://github.com/$repo.git"
   git fetch --depth 1 origin "$commit"
   git checkout "$commit"
   git submodule update --init --recursive --depth 1
   docker build -f "$cloned/$dockerfile" -t "$imageName" "$context"
   ```

   **Browser Source**:
   ```bash
   docker tag "$baseImage" "node-$baseImage"
   docker build \
     --build-arg BASE_IMAGE="node-$baseImage" \
     --build-arg BROWSER="$browser" \
     -t "$imageName" "$context"
   ```

   c. **Apply patches** (if specified):
   ```bash
   cd "$source_dir"
   patch -p1 < "$patch_file"
   ```

**YAML Files Generated**:
- **`docker-build-*.yaml`** - Per-implementation build configuration
  - Schema: [docs/docker-build-schema.md](docker-build-schema.md)
  - Location: `$CACHE_DIR/build-yamls/docker-build-perf-<id>.yaml`
  - One file per implementation

**Code Location**:
- Main: `perf/run.sh:535-561`
- Section builder: `lib/lib-image-building.sh:23-157`
- Single builder: `lib/build-single-image.sh`

**Build Strategies**:
- **Local**: Direct build from filesystem
- **GitHub (snapshot)**: Download ZIP, extract, build
- **GitHub (submodules)**: Git clone, fetch commit, build
- **Browser**: Tag base image, build browser wrapper

---

### Phase 8: Run Tests (Lines ~563-669)

**Purpose**: Execute all tests and collect results

**Key Actions**:

1. **Start global services**:
   ```bash
   start_redis_service "${TEST_TYPE}-network" "${TEST_TYPE}-redis"
   ```
   - Creates Docker network (e.g., `perf-network`)
   - Starts Redis container for peer coordination

2. **Get test count**:
   ```bash
   TEST_COUNT=$(yq eval '.tests | length' test-matrix.yaml)
   ```

3. **For each test**:

   a. **Sequential** (perf, hole-punch with WORKER_COUNT=1):
   ```bash
   for ((i=0; i<TEST_COUNT; i++)); do
     bash "${SCRIPT_DIR}/run-single-test.sh" "$i" "tests" "$RESULTS_FILE"
   done
   ```

   b. **Parallel** (transport, hole-punch with WORKER_COUNT>1):
   ```bash
   for ((i=0; i<TEST_COUNT; i++)); do
     bash "${SCRIPT_DIR}/run-single-test.sh" "$i" "tests" "$RESULTS_FILE" &

     # Limit concurrent jobs
     while [ $(jobs -r | wc -l) -ge $WORKER_COUNT ]; do
       sleep 0.1
     done
   done
   wait  # Wait for all background jobs
   ```

4. **Inside run-single-test.sh**:

   a. **Read test configuration**:
   ```bash
   DIALER_ID=$(yq eval ".tests[$i].dialer.id" test-matrix.yaml)
   LISTENER_ID=$(yq eval ".tests[$i].listener.id" test-matrix.yaml)
   TRANSPORT=$(yq eval ".tests[$i].transport" test-matrix.yaml)
   SECURE_CHANNEL=$(yq eval ".tests[$i].secureChannel" test-matrix.yaml)
   MUXER=$(yq eval ".tests[$i].muxer" test-matrix.yaml)
   ```

   b. **Compute TEST_KEY** (for Redis namespacing):
   ```bash
   TEST_KEY=$(echo -n "$TEST_NAME" | sha256sum | cut -c1-8)
   # Example: "a5b50d5e"
   ```

   c. **Generate docker-compose.yaml**:
   ```yaml
   name: rust-v0_56_x_rust-v0_56__tcp__noise__yamux_

   networks:
     perf-network:
       external: true
     test-network:
       driver: bridge
       ipam:
         config:
           - subnet: 10.5.0.0/24

   services:
     listener:
       image: perf-implementations-rust-v0.56
       networks:
         test-network:
           ipv4_address: 10.5.0.10
         perf-network:
       environment:
         - IS_DIALER=false
         - REDIS_ADDR=perf-redis:6379
         - TEST_KEY=a5b50d5e
         - TRANSPORT=tcp
         - SECURE_CHANNEL=noise
         - MUXER=yamux
         - LISTENER_IP=10.5.0.10

     dialer:
       image: perf-implementations-rust-v0.56
       depends_on:
         - listener
       networks:
         test-network:
         perf-network:
       environment:
         - IS_DIALER=true
         - REDIS_ADDR=perf-redis:6379
         - TEST_KEY=a5b50d5e
         - TRANSPORT=tcp
         - SECURE_CHANNEL=noise
         - MUXER=yamux
         - UPLOAD_BYTES=1073741824
         - DOWNLOAD_BYTES=1073741824
         - ITERATIONS=10
   ```

   **Hole-Punch** adds relay and routers:
   ```yaml
   services:
     relay:
       # On WAN network (10.x.x.68)
     dialer-router:
       # NAT router for dialer LAN
     listener-router:
       # NAT router for listener LAN
     dialer:
       # On dialer LAN (10.x.x.99)
     listener:
       # On listener LAN (10.x.x.131)
   ```

   d. **Run test**:
   ```bash
   timeout 300 docker compose -f "$COMPOSE_FILE" up \
     --exit-code-from dialer \
     --abort-on-container-exit
   ```

   e. **Extract results** from dialer logs:
   ```bash
   DIALER_LOGS=$(docker compose -f "$COMPOSE_FILE" logs dialer)
   DIALER_YAML=$(echo "$DIALER_LOGS" | grep -E "dialer.*\\| (upload:|download:|latency:)" | sed 's/^.*| //')
   ```

   f. **Write per-test result**:
   ```bash
   cat > "results/${TEST_NAME}.yaml" <<EOF
   test: ${TEST_NAME}
   dialer: ${DIALER_ID}
   listener: ${LISTENER_ID}
   transport: ${TRANSPORT}
   secureChannel: ${SECURE_CHANNEL}
   muxer: ${MUXER}
   status: $([ $? -eq 0 ] && echo "pass" || echo "fail")
   duration: ${TEST_DURATION}s

   # Measurements from dialer
   ${DIALER_YAML}
   EOF
   ```

   g. **Append to combined results** (with file locking):
   ```bash
   (
     flock -x 200
     cat >> "results.yaml.tmp" <<EOF
     - name: ${TEST_NAME}
       dialer: ${DIALER_ID}
       listener: ${LISTENER_ID}
       ...
   EOF
   ) 200>/tmp/results.lock
   ```

   h. **Cleanup**:
   ```bash
   docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
   ```

5. **Stop global services**:
   ```bash
   stop_redis_service "${TEST_TYPE}-network" "${TEST_TYPE}-redis"
   ```

**YAML Files Generated**:
- **`results/<test-name>.yaml`** - Per-test results
  - Schema: [docs/results-schema.md](results-schema.md)
  - Location: `$TEST_PASS_DIR/results/<test-name>.yaml`
  - One file per test

- **`results.yaml.tmp`** - Temporary aggregated results
  - Location: `$TEST_PASS_DIR/results.yaml.tmp`
  - Intermediate file, replaced by final results.yaml in Phase 9

**Code Location**:
- Main loop: `perf/run.sh:563-669`
- Single test: `perf/lib/run-single-test.sh`

---

### Phase 9: Collect Results (Lines ~671-785)

**Purpose**: Aggregate all test results and generate final report

**Key Actions**:

1. **Count pass/fail**:
   ```bash
   PASSED=$(yq eval '[.[] | select(.status == "pass")] | length' results.yaml.tmp)
   FAILED=$(yq eval '[.[] | select(.status == "fail")] | length' results.yaml.tmp)
   TOTAL=$((PASSED + FAILED))
   ```

2. **Calculate duration**:
   ```bash
   STARTED_AT=$(cat "${TEST_PASS_DIR}/.start_time")
   COMPLETED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   DURATION=$(calculate_duration "$STARTED_AT" "$COMPLETED_AT")
   ```

3. **Get system info**:
   ```bash
   PLATFORM=$(uname -m)
   OS=$(uname -s)
   ```

4. **Generate final results.yaml**:
   ```bash
   cat > "${TEST_PASS_DIR}/results.yaml" <<EOF
   metadata:
     testPass: ${TEST_PASS_NAME}
     startedAt: ${STARTED_AT}
     completedAt: ${COMPLETED_AT}
     duration: ${DURATION}
     platform: ${PLATFORM}
     os: ${OS}
     workerCount: ${WORKER_COUNT}

   summary:
     total: ${TOTAL}
     passed: ${PASSED}
     failed: ${FAILED}

   tests:
   EOF

   # Append test results from temporary file
   yq eval '.[]' results.yaml.tmp >> results.yaml
   ```

5. **Display summary**:
   ```
   ================================================================================
   Test Results Summary
   ================================================================================

   Total:  156
   Passed: 148 ✓
   Failed: 8   ✗

   Failed Tests:
     • go-v0.45 x go-v0.45 (tcp, noise, yamux)
     • js-v3.x x js-v3.x (tcp, noise, mplex)
     ...
   ```

**YAML Files Generated**:
- **`results.yaml`** - Final aggregated results
  - Schema: [docs/results-schema.md](results-schema.md)
  - Location: `$TEST_PASS_DIR/results.yaml`

**Code Location**:
- `perf/run.sh:671-785`
- `transport/run.sh:671-785`
- `hole-punch/run.sh:671-785`

---

### Phase 10: Generate Dashboard (Lines ~787-822)

**Purpose**: Create HTML dashboard from results

**Key Actions**:

1. **Call dashboard generator**:
   ```bash
   bash "${SCRIPT_DIR}/generate-dashboard.sh" "${TEST_PASS_DIR}"
   ```

2. **Inside generate-dashboard.sh**:

   a. **Read results.yaml**:
   ```bash
   TESTS=$(yq eval '.tests[]' results.yaml)
   ```

   b. **Generate HTML**:
   - **Perf**: Interactive charts with bandwidth/latency comparisons
   - **Transport**: Results table with pass/fail matrix
   - **Hole-Punch**: Results table with latency measurements

3. **Perf-specific: Generate box plots** (requires gnuplot):
   ```bash
   bash "${SCRIPT_DIR}/generate-boxplot.sh" "${TEST_PASS_DIR}"
   ```

**Files Generated**:
- **`results.html`** - HTML dashboard (all test types)
- **`charts.html`** - Interactive charts (perf only)
- **`boxplot.png`** - Box plot visualization (perf only)

**Code Location**:
- Main: `perf/run.sh:787-822`
- Dashboard: `perf/lib/generate-dashboard.sh`
- Charts: `perf/lib/generate-boxplot.sh`

---

### Phase 11: Create Snapshot (Lines ~824-838)

**Purpose**: Package test pass for sharing or archiving

**Conditional**: Only if `--snapshot` flag was used

**Key Actions**:

1. **Modify inputs.yaml** for snapshot context:
   ```bash
   modify_inputs_for_snapshot "${TEST_PASS_DIR}/inputs.yaml"
   ```

   Changes:
   - `IMAGES_YAML`: `./images.yaml`
   - `CACHE_DIR`: `./`
   - `TEST_RUN_DIR`: `./re-run`
   - `SCRIPT_DIR`: `./lib`
   - `SCRIPT_LIB_DIR`: `./lib`
   - Remove `--snapshot` from commandLineArgs

2. **Copy libraries and scripts**:
   ```bash
   cp -r "${SCRIPT_LIB_DIR}" "${TEST_PASS_DIR}/lib"
   cp -r "${SCRIPT_DIR}"/* "${TEST_PASS_DIR}/lib/"
   ```

3. **Create ZIP archive**:
   ```bash
   cd "${TEST_RUN_DIR}"
   zip -r "${TEST_PASS_NAME}.zip" "${TEST_PASS_NAME}"
   ```

4. **Snapshot contents**:
   ```
   perf-e5b6ea57-185931-28-12-2025.zip
   └── perf-e5b6ea57-185931-28-12-2025/
       ├── inputs.yaml          # Modified for snapshot
       ├── images.yaml          # Copied from source
       ├── test-matrix.yaml     # Generated matrix
       ├── results.yaml         # Test results
       ├── results.html         # Dashboard
       ├── lib/                 # All library scripts
       ├── logs/                # Per-test logs
       ├── results/             # Per-test results
       └── docker-compose/      # Generated compose files
   ```

5. **Usage**:
   ```bash
   unzip perf-e5b6ea57-185931-28-12-2025.zip
   cd perf-e5b6ea57-185931-28-12-2025
   ./run.sh  # Re-runs with captured configuration
   ```

**Files Generated**:
- **`<test-pass-name>.zip`** - Complete test pass archive
  - Location: `$TEST_RUN_DIR/<test-pass-name>.zip`

**Code Location**:
- Main: `perf/run.sh:824-838`
- Snapshot: `lib/lib-snapshot-creation.sh`

---

## YAML Files Summary

### Input Files (User-Provided)

| File | Location | Schema | Purpose |
|------|----------|--------|---------|
| `images.yaml` | `<test-type>/images.yaml` | [images-yaml-schema.md](images-yaml-schema.md) | Define implementations, transports, secure channels, muxers |
| `inputs.yaml` | `./ ` (optional) | [inputs-schema.md](inputs-schema.md) | Load previous test configuration |

### Generated Files (Test Framework)

| File | Location | Schema | Generated In | Purpose |
|------|----------|--------|--------------|---------|
| `inputs.yaml` | `$TEST_PASS_DIR/` | [inputs-schema.md](inputs-schema.md) | Phase 4 | Capture test configuration for reproducibility |
| `test-matrix.yaml` | `$TEST_PASS_DIR/` | [test-matrix-schema.md](test-matrix-schema.md) | Phase 5 | Define all test combinations to execute |
| `docker-build-*.yaml` | `$CACHE_DIR/build-yamls/` | [docker-build-schema.md](docker-build-schema.md) | Phase 7 | Per-implementation Docker build configuration |
| `results/<test-name>.yaml` | `$TEST_PASS_DIR/results/` | [results-schema.md](results-schema.md) | Phase 8 | Per-test results |
| `results.yaml` | `$TEST_PASS_DIR/` | [results-schema.md](results-schema.md) | Phase 9 | Aggregated test results with metadata |

### Copied Files

| File | From | To | Copied In |
|------|------|----|-----------|
| `images.yaml` | Source | `$TEST_PASS_DIR/` | Phase 5 |
| `test-matrix.yaml` | Generated | `$CACHE_DIR/test-run-matrix/` | Phase 5 (cache) |

---

## Test-Type-Specific Differences

### Perf Tests

**Unique Characteristics**:
- Sequential execution (WORKER_COUNT=1)
- Baseline tests in addition to main tests
- Performance measurements (bandwidth, latency)
- Two separate result phases: baselines → tests

**Unique Files**:
- `baseline-results.yaml.tmp` - Temporary baseline results

### Transport Tests

**Unique Characteristics**:
- Parallel execution (WORKER_COUNT=$(nproc))
- Browser implementations (dialOnly)
- GitHub sources with patches
- Simple pass/fail (no measurements)

**Unique Features**:
- Many implementations (40+)
- Cross-implementation testing
- Browser support

### Hole-Punch Tests

**Unique Characteristics**:
- Parallel execution (WORKER_COUNT=$(nproc))
- 5-container topology per test
- Unique subnets per test (NAT simulation)
- DCUtR protocol measurements

**Unique Files**:
- Router implementations in images.yaml
- Relay implementations in images.yaml

**Unique Test Matrix Fields**:
- relay, dialerRouter, listenerRouter

---

## Caching Strategy

### What Gets Cached

| Item | Cache Location | Cache Key | Invalidate When |
|------|----------------|-----------|-----------------|
| Test Matrix | `/srv/cache/test-run-matrix/` | Hash of images.yaml + filters | images.yaml or filters change |
| GitHub Snapshots | `/srv/cache/snapshots/` | Commit hash | Never (immutable) |
| Git Repos | `/srv/cache/git-repos/` | Repo + commit hash | Never (immutable) |
| Docker Images | Docker daemon | Image name | `--force-image-rebuild` |

### Cache Benefits

1. **Test Matrix**: Saves 5-10 seconds on repeated runs
2. **GitHub Snapshots**: Saves 1-5 seconds per implementation
3. **Git Repos**: Saves 10-30 seconds per implementation with submodules
4. **Docker Images**: Saves 30-300 seconds per image

---

## Error Handling

### Test Failures

Individual test failures don't stop the run:
- Failed test gets `status: fail`
- Other tests continue
- Final summary shows pass/fail counts

### Fatal Errors

These stop the entire run:
- Missing dependencies (Docker, yq, etc.)
- Invalid images.yaml syntax
- Docker build failures
- Redis service failures

---

## Performance Considerations

### Parallel Execution

- **Transport/Hole-Punch**: WORKER_COUNT=$(nproc) for fast execution
- **Perf**: WORKER_COUNT=1 for accurate measurements

### Network Isolation

- Each test gets isolated Docker network
- Unique subnets prevent cross-test interference
- Redis on shared network for coordination

### Resource Usage

- **Memory**: ~1-2GB per parallel test
- **CPU**: One core per parallel test
- **Disk**: ~100MB per test pass directory

---

## See Also

- **[docs/test-matrix-schema.md](test-matrix-schema.md)** - test-matrix.yaml schema
- **[docs/images-yaml-schema.md](images-yaml-schema.md)** - images.yaml schema
- **[docs/docker-build-schema.md](docker-build-schema.md)** - docker-build-*.yaml schema
- **[docs/inputs-schema.md](inputs-schema.md)** - inputs.yaml schema
- **[docs/results-schema.md](results-schema.md)** - results.yaml schema
- **[CLAUDE.md](../CLAUDE.md)** - Comprehensive framework documentation
