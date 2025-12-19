# Scripts Design Documentation

## Introduction

This document explains how the test infrastructure works in the test-plans repository. It covers the complete execution flow from running tests to creating snapshots, with detailed documentation of all common functions.

**Purpose**: Provide a clear understanding of:
- How tests are executed from start to finish
- How filtering, caching, and building work
- How to add new test suites
- Reference for all common functions

**Target audience**: Developers maintaining or extending the test infrastructure.

---

## Test Execution Flow

### Overview

When you run `./run_tests.sh`, the system goes through a well-defined sequence of steps from argument parsing to final results.

### Complete Execution Flow

#### Step 1: Argument Parsing
**Location**: `run_tests.sh` lines 64-91

Parses command-line options and sets environment variables.

**Options processed**:
- `--test-select VALUE` - Select tests
- `--test-ignore VALUE` - Ignore tests
- `--workers VALUE` - Parallel workers
- `--debug` - Debug mode
- `--force-matrix-rebuild` - Bypass matrix cache
- `--force-image-rebuild` - Rebuild images
- Test-type-specific options (relay, router, baseline, iterations)

**Output**: Environment variables set (TEST\_SELECT, WORKERS, DEBUG, etc.)

#### Step 2: Dependency Check (if `--check-deps`)
**Function called**: `bash ../lib/check-dependencies.sh`

**Validates**:
- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget, unzip

**Output**: Exit 0 if satisfied, exit 1 if missing

#### Step 3: List Commands (if `--list-impls`, `--list-tests`, etc.)

**For** `--list-impls`:
- **Function**: `yq eval '.implementations[].id' impls.yaml`
- **Output**: List of implementation IDs

**For** `--list-tests`:
- **Functions**: `bash lib/generate-tests.sh` then extract `.tests[].name`
- **Output**: List of test names

**Result**: Displays information and exits

#### Step 4: Load Aliases
**Function called**: `load_aliases()` from `lib-test-aliases.sh`

**Process**:
- Reads `test-aliases` section from impls.yaml
- Populates global ALIASES associative array

**Example**:
```yaml
test-aliases:
  - alias: "rust"
    value: "rust-v0.56|rust-v0.55"
```

**Output**: ALIASES["rust"] = "rust-v0.56|rust-v0.55"

#### Step 5: Expand Filters
**Function called**: `expand_filter_string(filter, all_names_array)` from `lib-filter-engine.sh`

**For each filter** (TEST\_SELECT, TEST\_IGNORE, RELAY\_SELECT, etc.):

**Input**: Raw filter string (e.g., `"~rust|!go"`)

**Process**:
1. Recursively expands aliases (supports nesting)
2. Handles inversions (`!value`, `!~alias`)
3. Deduplicates results
4. Detects circular references

**Output**: Expanded filter string (e.g., `"rust-v0.56|rust-v0.55|python-v0.4"`)

**Example**:
```bash
Input:  "~rust|go-v0.45"
Expands: ~rust → rust-v0.56|rust-v0.55
Output: "go-v0.45|rust-v0.55|rust-v0.56"
```

#### Step 6: Generate Test Matrix
**Function called**: `bash lib/generate-tests.sh`

**Inputs**:
- Expanded filter strings
- DEBUG flag
- FORCE\_MATRIX\_REBUILD flag

**Process**:
1. Compute cache key: `compute_cache_key()` from `lib-test-caching.sh`
2. Check cache: `check_and_load_cache()`
3. If cache hit: Load and exit
4. If cache miss:
   - Load implementations into memory
   - Generate all valid combinations (test-type-specific)
   - Apply filtering: `matches_select()`, `should_ignore()`
   - Save matrix: `save_to_cache()`

**Output**: `test-matrix.yaml` with all test combinations

#### Step 7: Build Docker Images
**Function called**: `bash lib/build-images.sh`

**Process**:
1. Extract unique implementations from test-matrix.yaml
2. For each implementation:
   - Generate build YAML
   - Call: `bash lib/build-single-image.sh <yaml>`
   - Which calls: `build_from_github()` or `build_from_github_with_submodules()`

**Output**: Docker images tagged as `<test-type>-<impl-id>`

#### Step 8: Run Tests in Parallel
**Execution**: `seq 0 $((test_count - 1)) | xargs -P $WORKERS bash -c 'run_test {}'`

**For each test** (index 0 to N-1):

**Function called**: `bash lib/run-single-test.sh <index>`

**Process**:
1. Extract test details from test-matrix.yaml (dialer, listener, transport, etc.)
2. Start Docker containers
3. Wait for test completion
4. Capture results (status, duration, metrics)
5. Append to results.yaml.tmp with file locking

**Output**: results.yaml.tmp (partial results, one entry per test)

#### Step 9: Collect Results
**Process**:
1. Aggregate results.yaml.tmp
2. Calculate summary (total, passed, failed)
3. Add metadata (timestamps, platform, duration, worker count)

**Output**: `results.yaml` (structured test results)

#### Step 10: Generate Dashboard
**Function called**: `bash lib/generate-dashboard.sh`

**Inputs**: results.yaml

**Process**:
1. Extract metadata and summary
2. Generate results.md (summary + visualizations)
3. Generate LATEST\_TEST\_RESULTS.md (detailed tables)
4. Generate results.html (if pandoc available)
5. For perf: Generate box plots

**Outputs**:
- results.md
- LATEST\_TEST\_RESULTS.md
- results.html

#### Step 11: Create Snapshot (if `--snapshot`)
**Function called**: `bash lib/create-snapshot.sh`

**Process** (uses common libraries):
1. Validate inputs
2. Create snapshot directory structure
3. Copy configuration, results, scripts
4. Copy GitHub sources (ZIPs + git clones)
5. Save Docker images
6. Generate re-run.sh
7. Generate README and settings
8. Validate snapshot complete

**Output**: Self-contained snapshot directory in `/srv/cache/test-runs/`

#### Step 12: Display Summary
**Output to user**:
- Total tests, passed, failed
- Pass rate percentage
- Duration
- Snapshot location (if created)

---

## Test Filtering

### Filter Syntax

Test filtering supports four pattern types:

1. **Value**: `rust-v0.56` - Matches names containing the value
2. **Alias**: `~rust` - Expands to alias value from impls.yaml
3. **Inverted value**: `!rust` - Matches names NOT containing the value
4. **Inverted alias**: `!~rust` - Expands alias, matches names NOT in expansion

**Combining patterns**: Use pipe (`|`) to combine multiple patterns.

**Examples**:
- `~rust` → Expands to all rust versions
- `!~rust` → All implementations except rust
- `~rust|go-v0.45` → Rust versions plus go-v0.45
- `!python` → All implementations not containing "python"

### Two-Step Filtering Pattern

**Critical**: All filtering follows this pattern:

**Step 1 - SELECT**: Applied to ALL entity names → selected\_set
**Step 2 - IGNORE**: Applied to selected\_set (NOT to all names) → final\_set

**Example**:
```
Command: --test-select '~rust' --test-ignore 'v0.56'

Step 1 (SELECT):
  Input: [all implementations]
  Filter: ~rust → rust-v0.56|rust-v0.55
  Output: rust-v0.56, rust-v0.55

Step 2 (IGNORE):
  Input: rust-v0.56, rust-v0.55  # Only from selected set!
  Filter: v0.56
  Output: rust-v0.55

Final: Only rust-v0.55 tests will run
```

### Key Functions

#### expand\_filter\_string(filter, all\_names\_array)

- **Inputs**:
  - `filter`: Raw filter string (may contain `~alias`, `!value`, `!~alias`)
  - `all_names_array`: Name of array variable containing all possible entity names
- **Outputs**:
  - Fully expanded, deduplicated pipe-separated string
- **Description**: Main entry point for filter processing. Recursively expands aliases (supports nesting), handles inversions (`!value` expands to all non-matching names, `!~alias` expands alias then negates), detects circular references, and deduplicates results. Used by all generate-tests.sh scripts.
- **Where**: `lib-filter-engine.sh`

#### filter\_names(input\_names, all\_names, select\_filter, ignore\_filter)

- **Inputs**:
  - `input_names`: Name of array variable with names to filter
  - `all_names`: Name of array variable with all possible names (for negation)
  - `select_filter`: Raw SELECT filter string
  - `ignore_filter`: Raw IGNORE filter string
- **Outputs**:
  - Filtered names (one per line via stdout)
- **Description**: Implements complete two-step filtering pattern. First applies select filter to all input names to get selected set, then applies ignore filter to selected set (not to all names) to get final set. Ensures correct filtering semantics.
- **Where**: `lib-filter-engine.sh`

#### filter\_matches(name, filter\_string)

- **Inputs**:
  - `name`: Single name to check
  - `filter_string`: Expanded filter string (pipe-separated patterns)
- **Outputs**:
  - Exit code: 0 if matches, 1 if no match
- **Description**: Generic matching function that checks if name contains any pattern in filter string. Works for any entity type (implementations, relays, routers, baselines). Used throughout generate-tests.sh scripts.
- **Where**: `lib-filter-engine.sh`

#### load\_aliases()

- **Inputs**: None (reads `impls.yaml` from current directory)
- **Outputs**: Populates global ALIASES associative array
- **Description**: Loads test-aliases section from impls.yaml into memory for fast alias expansion. Must be called before any filter expansion. Used by all generate-tests.sh scripts.
- **Where**: `lib-test-aliases.sh`

---

## Test Matrix Generation

### Overview

Test matrices define all test combinations to execute. Generation is cached using content-addressed keys for performance.

### Generation Flow

1. **Load Implementations**
   - Reads impls.yaml using yq
   - Loads into associative arrays for O(1) lookup
   - Arrays: impl\_transports, impl\_secureChannels, impl\_muxers

2. **Expand Filters**
   - Calls `expand_filter_string()` for TEST\_SELECT, TEST\_IGNORE
   - Also for entity-specific filters (RELAY\_SELECT, BASELINE\_SELECT, etc.)

3. **Check Cache**
   - Computes cache key from impls.yaml + filters + debug flag
   - Checks `/srv/cache/test-matrix/<hash>.yaml`
   - If exists: Copies to output and returns

4. **Generate Combinations** (if cache miss)
   - Test-type-specific logic generates all valid combinations
   - **Transport**: dialer × listener × transport × secure × muxer
   - **Hole-Punch**: + relay × dialer\_router × listener\_router (8D)
   - **Perf**: Separate baseline and main test matrices

5. **Apply Filtering**
   - For each potential test:
     - Check `matches_select(test_name)` - must match SELECT filter
     - Check `should_ignore(test_name)` - must NOT match IGNORE filter
     - If both pass: Add to matrix

6. **Save Matrix**
   - Write test-matrix.yaml
   - Save to cache for future runs

### Key Functions

#### compute\_cache\_key(select, ignore, relay\_select, relay\_ignore, router\_select, router\_ignore, debug)

- **Inputs**:
  - `select`: TEST\_SELECT filter string
  - `ignore`: TEST\_IGNORE filter string
  - `relay_select`: RELAY\_SELECT filter (hole-punch)
  - `relay_ignore`: RELAY\_IGNORE filter (hole-punch)
  - `router_select`: ROUTER\_SELECT filter (hole-punch)
  - `router_ignore`: ROUTER\_IGNORE filter (hole-punch)
  - `debug`: Debug mode flag
- **Outputs**:
  - SHA-256 hash (64 hex characters)
- **Description**: Creates content-based cache key by hashing impls.yaml content concatenated with all parameters using double-pipe (`||`) delimiter to prevent ambiguous collisions. Used to determine if test matrix can be loaded from cache.
- **Where**: `lib-test-caching.sh`

#### check\_and\_load\_cache(cache\_key, cache\_dir, output\_dir)

- **Inputs**:
  - `cache_key`: SHA-256 hash from compute\_cache\_key()
  - `cache_dir`: Cache directory path (usually `/srv/cache`)
  - `output_dir`: Output directory for test-matrix.yaml
- **Outputs**:
  - Exit code: 0 if cache hit, 1 if cache miss
  - Side effect: Copies test-matrix.yaml to output\_dir if hit
- **Description**: Checks if cached test matrix exists for given key. If found, copies to output directory providing 10-100x speedup. Cache hit takes ~50-200ms vs ~2-5 seconds for generation.
- **Where**: `lib-test-caching.sh`

#### save\_to\_cache(output\_dir, cache\_key, cache\_dir)

- **Inputs**:
  - `output_dir`: Directory containing test-matrix.yaml to cache
  - `cache_key`: SHA-256 hash
  - `cache_dir`: Cache directory path
- **Outputs**:
  - None (side effect: file copied to cache)
- **Description**: Saves generated test-matrix.yaml to cache directory using cache key as filename. Enables fast loading on subsequent runs with same configuration.
- **Where**: `lib-test-caching.sh`

#### matches\_select(test\_name)

- **Inputs**:
  - `test_name`: Full test name string
- **Outputs**:
  - Exit code: 0 if matches, 1 if no match
- **Description**: Checks if test name matches any pattern in SELECT\_PATTERNS array (pre-populated from expanded filter). Uses substring matching. Returns true if no select patterns defined (include all).
- **Where**: `lib-test-filtering.sh`

#### should\_ignore(test\_name)

- **Inputs**:
  - `test_name`: Full test name string
- **Outputs**:
  - Exit code: 0 if should ignore, 1 if keep
- **Description**: Checks if test name matches any pattern in IGNORE\_PATTERNS array. Handles inverted patterns for dialer/listener matching (ensures both sides match for negated filters). Returns false if no ignore patterns defined.
- **Where**: `lib-test-filtering.sh`

### Test Matrix Structure

Generated test-matrix.yaml contains:

```yaml
metadata:
  generatedAt: 2025-12-16T10:00:00Z
  select: "rust-v0.56|rust-v0.55"
  ignore: ""
  totalTests: 184
  debug: false

tests:
  - name: "rust-v0.56 x rust-v0.55 (tcp, noise, yamux)"
    dialer: rust-v0.56
    listener: rust-v0.55
    transport: tcp
    secureChannel: noise
    muxer: yamux
```

---

## GitHub Source Handling

### Overview

Implementations can be built from GitHub repositories using either ZIP downloads (for simple repos) or git clones (for repos with submodules).

### Source Type Detection

Check `requiresSubmodules` flag in impls.yaml:

```yaml
implementations:
  - id: c-v0.0.1
    source:
      type: github
      repo: Pier-Two/c-libp2p
      commit: 23a617223a3bbfb4b2af8f219f389e440b9c1ac2
      requiresSubmodules: true  # Triggers git clone
```

**Decision**:
- If `requiresSubmodules: true` → Use git clone
- Otherwise → Use ZIP download

### ZIP Snapshot Flow

**Used for**: Most implementations (no submodules)

**Step 1 - Download**:
- **Function**: `download_github_snapshot(repo, commit, cache_dir)`
- **Downloads**: `https://github.com/<repo>/archive/<commit>.zip`
- **Caches**: `/srv/cache/snapshots/<commit>.zip`

**Step 2 - Extract**:
- **Function**: `extract_github_snapshot(snapshot_file, repo_name, commit)`
- **Extracts**: To temporary directory
- **Returns**: Work directory path

**Step 3 - Build**:
- Uses extracted source as build context
- Runs docker build

### Git Clone Flow (with Submodules)

**Used for**: Implementations requiring submodules (e.g., c-v0.0.1)

**Step 1 - Clone**:
- **Function**: `clone_github_repo_with_submodules(repo, commit, cache_dir)`
- **Executes**:
  ```bash
  git clone --depth 1 https://github.com/<repo>.git
  git submodule update --init --recursive --depth 1
  ```
- **Caches**: `/srv/cache/git-repos/<repo>-<commit>/`

**Step 2 - Build**:
- Uses git clone directory as build context
- All submodules available during build

### Key Functions

#### get\_required\_github\_sources()

- **Inputs**: None (reads impls.yaml from current directory)
- **Outputs**: TSV format: `commit<TAB>repo<TAB>requiresSubmodules`
- **Description**: Extracts all GitHub-based implementations with their source requirements. Used to determine which ZIP snapshots or git clones are needed for building or snapshot creation.
- **Where**: `lib-github-snapshots.sh`

#### copy\_github\_sources\_to\_snapshot(snapshot\_dir, cache\_dir)

- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `cache_dir`: Source cache directory (usually `/srv/cache`)
- **Outputs**:
  - Exit code: 0 if all copied, 1 if any missing
  - Prints: Count of ZIPs and git clones copied
- **Description**: Copies GitHub sources to snapshot directories. ZIP files go to snapshots/, git clones go to git-repos/. Handles both types automatically based on requiresSubmodules flag. Used by create-snapshot.sh scripts.
- **Where**: `lib-github-snapshots.sh`

#### prepare\_git\_clones\_for\_build(snapshot\_dir, cache\_dir)

- **Inputs**:
  - `snapshot_dir`: Snapshot directory containing git-repos/
  - `cache_dir`: Target cache directory
- **Outputs**: None (side effect: git clones copied to cache)
- **Description**: Makes git clones from snapshot available to build system by copying them to cache directory. Called during snapshot re-run to prepare sources for image building.
- **Where**: `lib-github-snapshots.sh`

#### clone\_github\_repo\_with\_submodules(repo, commit, cache\_dir)

- **Inputs**:
  - `repo`: Repository name (e.g., "libp2p/rust-libp2p")
  - `commit`: Commit SHA
  - `cache_dir`: Cache directory for storing clone
- **Outputs**:
  - Work directory path (caller must clean up)
  - Exit code: 0 if success, 1 if failed
- **Description**: Clones GitHub repository and initializes all submodules recursively. Uses --depth 1 for efficiency. Caches clone in git-repos/ for reuse. Handles nested submodules.
- **Where**: `lib-image-building.sh`

### Caching

**ZIP Snapshots**: `/srv/cache/snapshots/<commit>.zip` (keyed by Git SHA-1, 40 chars)
**Git Clones**: `/srv/cache/git-repos/<repo>-<commit>/` (includes .git directory and all submodules)

Both are persistent across test runs and snapshots.

---

## Docker Image Building

### Overview

Docker images are built from implementation sources (GitHub ZIP, GitHub git, local filesystem, or browser) using a YAML-driven build system.

### Build Flow

**Step 1 - Generate Build YAML** (in build-images.sh):

Creates build configuration file:
```yaml
image_name: transport-interop-rust-v0.56
build_context: /tmp/work/rust-libp2p/interop-tests
dockerfile: Dockerfile.native
source:
  type: github
  repo: libp2p/rust-libp2p
  commit: abc123...
  requiresSubmodules: false
cacheDir: /srv/cache
```

**Step 2 - Execute Build** (build-single-image.sh):

Reads build YAML and calls appropriate build function:
- GitHub (no submodules): `build_from_github()`
- GitHub (with submodules): `build_from_github_with_submodules()`
- Local: `build_from_local()`
- Browser: Uses browser Docker image

**Step 3 - Docker Build**:

Executes `docker build` with:
- Build context from source (ZIP extract, git clone, or local path)
- Dockerfile from impls.yaml
- Tags image as `<test-type>-<impl-id>`

### Key Functions

#### build\_from\_github(yaml\_file, output\_filter)

- **Inputs**:
  - `yaml_file`: Path to build YAML configuration
  - `output_filter`: Output style ("normal" or "quiet")
- **Outputs**:
  - Exit code: 0 if success, 1 if failed
  - Docker image created and tagged
- **Description**: Builds Docker image from GitHub ZIP snapshot. Downloads snapshot if not cached, extracts to temporary directory, runs docker build with specified context and Dockerfile. Cleans up temporary files after build.
- **Where**: `lib-image-building.sh`

#### build\_from\_github\_with\_submodules(yaml\_file, output\_filter)

- **Inputs**:
  - `yaml_file`: Path to build YAML configuration
  - `output_filter`: Output style ("normal" or "quiet")
- **Outputs**:
  - Exit code: 0 if success, 1 if failed
  - Docker image created and tagged
- **Description**: Builds Docker image from git clone with submodules. Clones repository if not cached (with --recursive flag), or uses cached clone, then runs docker build. Ensures all submodules are initialized before building.
- **Where**: `lib-image-building.sh`

#### download\_github\_snapshot(repo, commit, cache\_dir)

- **Inputs**:
  - `repo`: Repository name (e.g., "libp2p/go-libp2p")
  - `commit`: Full commit SHA
  - `cache_dir`: Cache directory path
- **Outputs**:
  - Path to cached ZIP file
  - Exit code: 0 if success, 1 if download failed
- **Description**: Downloads GitHub repository archive as ZIP file. Checks cache first using commit SHA as key. If not cached, downloads from `https://github.com/<repo>/archive/<commit>.zip` and saves to cache.
- **Where**: `lib-image-building.sh`

### Image Naming Convention

**Format**: `<test-type>-<component>-<impl-id>`

**Examples**:
- `transport-interop-rust-v0.56`
- `hole-punch-peer-linux`
- `hole-punch-relay-linux`
- `hole-punch-router-linux`
- `perf-rust-v0.56`

---

## Caching System

### Overview

All artifacts use content-addressed caching for deduplication and performance optimization.

### Cache Directory Structure

```
/srv/cache/
├── snapshots/              # GitHub ZIP archives
│   └── <commit-sha>.zip    # Keyed by Git SHA-1 (40 hex chars)
├── git-repos/              # Git clones with submodules
│   └── <repo>-<commit>/    # Full git clone including .git
├── test-matrix/            # Generated test matrices
│   └── <sha256>.yaml       # Keyed by SHA-256 (64 hex chars)
├── build-yamls/            # Build configuration files
│   └── docker-build-<name>.yaml
└── test-runs/              # Test pass snapshots
    └── <test-type>-HHMMSS-DD-MM-YYYY/
```

### Cache Key Generation

**For test matrices**:

**Function**: `compute_cache_key()`

**Algorithm**:
1. Read impls.yaml content
2. Concatenate: `impls_content||TEST_SELECT||TEST_IGNORE||...||DEBUG`
3. Compute SHA-256 hash
4. Return 64-character hex string

**Why double-pipe** (`||`): Prevents ambiguous collisions where different parameter combinations could produce same concatenation.

**Example**:
```
Inputs: TEST_SELECT="rust", TEST_IGNORE="", DEBUG="false"
Key: sha256(impls.yaml||rust||||false)
Output: "6b10a3ee4f7c9d2a1e..."
```

**For GitHub snapshots**:
- ZIP files: Keyed by commit SHA (from Git, 40 characters)
- Git clones: Keyed by `<repo>-<commit>` (directory name)

### Cache Performance

**Cache hit**:
- Time: ~50-200ms (file copy)
- Benefit: Skips generation entirely

**Cache miss**:
- Time: ~2-5 seconds (generation + save)
- Next run: Will be cache hit

**Typical speedup**: 10-100x on cache hits

### Key Functions

#### compute\_cache\_key(...)

- **Inputs**: All filter parameters (up to 6), debug flag
- **Outputs**: SHA-256 hash string (64 characters)
- **Description**: Creates content-based cache identifier from impls.yaml and all parameters. Uses double-pipe delimiter between parameters to prevent collision ambiguity. Used before test matrix generation to check cache.
- **Where**: `lib-test-caching.sh`

#### check\_and\_load\_cache(cache\_key, cache\_dir, output\_dir)

- **Inputs**:
  - `cache_key`: SHA-256 hash
  - `cache_dir`: Cache directory (e.g., `/srv/cache`)
  - `output_dir`: Output directory for matrix file
- **Outputs**:
  - Exit code: 0 if hit (matrix loaded), 1 if miss
- **Description**: Checks if `/srv/cache/test-matrix/<key>.yaml` exists. If found, copies to output directory and returns success. Provides significant performance improvement by avoiding regeneration.
- **Where**: `lib-test-caching.sh`

#### save\_to\_cache(output\_dir, cache\_key, cache\_dir)

- **Inputs**:
  - `output_dir`: Directory with test-matrix.yaml to save
  - `cache_key`: SHA-256 hash
  - `cache_dir`: Cache directory
- **Outputs**: None (side effect: matrix saved to cache)
- **Description**: Copies test-matrix.yaml from output directory to cache using cache key as filename. Called after successful matrix generation to enable caching for future runs.
- **Where**: `lib-test-caching.sh`

---

## Snapshot Creation

### Overview

Snapshots are self-contained archives of test runs that include all files needed for exact reproduction: configuration, results, scripts, Docker images, and source code.

### Creation Flow (10 Steps)

#### Step 1: Validate Inputs
**Function**: `validate_snapshot_inputs(test_pass_dir, cache_dir)`

Checks that results.yaml, test-matrix.yaml, and impls.yaml exist.

#### Step 2: Create Directory Structure
**Function**: `create_snapshot_directory(snapshot_dir)`

Creates:
- `logs/` - Test execution logs
- `docker-compose/` - Generated compose files
- `docker-images/` - Saved Docker images
- `snapshots/` - GitHub ZIP archives
- `git-repos/` - Git clones with submodules
- `lib/` - Test scripts

#### Step 3: Copy Configuration
**Function**: `copy_config_files(snapshot_dir, test_pass_dir, test_type)`

Copies:
- impls.yaml
- test-matrix.yaml
- results.yaml, results.md, results.html
- LATEST\_TEST\_RESULTS.md
- Box plot images (perf only)

#### Step 4: Copy Scripts
**Function**: `copy_all_scripts(snapshot_dir, test_type)`

Copies:
- Test-specific scripts from `lib/`
- Common libraries from `../lib/`
- Makes all scripts executable

#### Step 5: Copy GitHub Sources
**Function**: `copy_github_sources_to_snapshot(snapshot_dir, cache_dir)`

Copies:
- ZIP snapshots → `snapshots/`
- Git clones → `git-repos/`
- Handles both types automatically

#### Step 6: Save Docker Images
**Function**: `save_docker_image(image_name, output_dir)` (called for each image)

Saves images as compressed tar files.

#### Step 7: Generate Re-run Script
**Function**: `generate_rerun_script(snapshot_dir, test_type, test_pass, original_options)`

Creates complete re-run.sh with:
- All filter options (11-17 depending on test type)
- Argument parsing
- Help text
- Image loading/building logic
- Test execution
- Results collection

#### Step 8: Generate Metadata
**Functions**: `create_settings_yaml()`, `generate_snapshot_readme()`

Creates:
- settings.yaml - Snapshot metadata
- README.md - Documentation and usage instructions

#### Step 9: Validate Snapshot
**Function**: `validate_snapshot_complete(snapshot_dir)`

Checks all required files are present.

#### Step 10: Display Summary
**Function**: `display_snapshot_summary(snapshot_dir)`

Shows:
- Snapshot location and size
- File counts (logs, images, ZIPs, git clones)
- Re-run command

### Snapshot Directory Structure

```
snapshot-HHMMSS-DD-MM-YYYY/
├── impls.yaml              # Implementation definitions
├── impls/                  # Local implementations (if any)
├── test-matrix.yaml        # Test combinations
├── results.yaml            # Structured results
├── results.md              # Markdown dashboard
├── results.html            # HTML visualization
├── LATEST_TEST_RESULTS.md  # Detailed results
├── settings.yaml           # Snapshot metadata
├── README.md               # Documentation
├── re-run.sh               # Re-run script (COMPLETE)
├── lib/                # Test-specific scripts
│   └── *.sh
├── ../lib/             # Common libraries
│   └── lib-*.sh
├── logs/                   # Test execution logs
├── docker-compose/         # Generated compose files
├── docker-images/          # Saved images (.tar.gz)
├── snapshots/              # GitHub ZIP archives
└── git-repos/              # Git clones with submodules
    └── c-libp2p-<commit>/
```

### Re-run.sh Capabilities

**Default re-run** (uses original settings):
```bash
./re-run.sh
```

**Re-run with different filters**:
```bash
# Transport
./re-run.sh --test-select '~rust' --workers 4

# Hole-punch
./re-run.sh --relay-select 'linux' --router-ignore 'chromium'

# Perf
./re-run.sh --baseline-select '~baselines' --iterations 20
```

**Force rebuild**:
```bash
./re-run.sh --force-image-rebuild --force-matrix-rebuild
```

**Preview tests**:
```bash
./re-run.sh --test-select '~go' --list-tests
```

### Key Functions

#### create\_snapshot\_directory(snapshot\_dir)

- **Inputs**: Snapshot directory path
- **Outputs**: Exit code (0=success, 1=already exists)
- **Description**: Creates complete snapshot directory structure including all subdirectories (logs, docker-compose, docker-images, snapshots, git-repos, scripts). Returns error if directory already exists to prevent overwriting.
- **Where**: `lib-snapshot-creation.sh`

#### copy\_config\_files(snapshot\_dir, test\_pass\_dir, test\_type)

- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `test_pass_dir`: Source test pass directory
  - `test_type`: Type of test ("transport", "hole-punch", or "perf")
- **Outputs**: None (side effect: files copied)
- **Description**: Copies all configuration and results files to snapshot. Includes impls.yaml, test-matrix.yaml, all results files, and test-type-specific files like box plot images for perf tests.
- **Where**: `lib-snapshot-creation.sh`

#### generate\_rerun\_script(snapshot\_dir, test\_type, test\_pass\_name, original\_options)

- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `test_type`: "transport", "hole-punch", or "perf"
  - `test_pass_name`: Name of test pass
  - `original_options`: Associative array name with original run options
- **Outputs**:
  - Creates re-run.sh file (executable, ~10-15KB)
- **Description**: Generates complete re-run.sh script with full option support (11-17 options depending on test type). Includes help text, argument parsing, validation, image handling, smart matrix regeneration, test execution, and results collection. Major improvement enabling snapshots to be re-run with different filters.
- **Where**: `lib-snapshot-rerun.sh`

#### save\_docker\_image(image\_name, output\_dir)

- **Inputs**:
  - `image_name`: Docker image name to save
  - `output_dir`: Output directory for tar file
- **Outputs**:
  - Exit code: 0 if success, 1 if image not found
  - Creates: `<image_name>.tar.gz` file
- **Description**: Saves Docker image as compressed tar file using `docker save | gzip`. Creates output directory if needed. Used by create-snapshot.sh to save all required images.
- **Where**: `lib-snapshot-images.sh`

---

## Adding a New Test Suite

### Overview

To add a new test type (e.g., "latency-tests"), you need to create 6 scripts plus configuration files.

### Required Scripts

#### 1. Main Orchestrator: `<test>/run_tests.sh` (~300 lines)

**Purpose**: Main entry point for running tests

**Must implement**:
- Argument parsing (standard + test-specific options)
- Dependency checking (call check-dependencies.sh)
- List commands (--list-impls, --list-tests)
- Alias loading and filter expansion
- Test matrix generation
- Docker image building
- Test execution (parallel with xargs)
- Results collection
- Dashboard generation
- Snapshot creation (if --snapshot)

**Standard options**:
- `--test-select VALUE` - Filter tests
- `--test-ignore VALUE` - Exclude tests
- `--workers VALUE` - Parallel workers (default: nproc)
- `--debug` - Debug mode
- `--force-matrix-rebuild` - Bypass matrix cache
- `--force-image-rebuild` - Rebuild all images
- `-y, --yes` - Skip confirmations
- `--check-deps` - Validate dependencies
- `--list-impls` - List implementations
- `--list-tests` - List tests
- `--help` - Show help

**Common library usage**:
```bash
source ../lib/lib-test-aliases.sh
source ../lib/lib-filter-engine.sh
source ../lib/lib-test-caching.sh

load_aliases
all_impl_ids=($(yq eval '.implementations[].id' impls.yaml))
TEST_SELECT=$(expand_filter_string "$TEST_SELECT" all_impl_ids)
```

#### 2. Test Matrix Generator: `<test>/lib/generate-tests.sh` (~200 lines)

**Purpose**: Generate test-matrix.yaml with all test combinations

**Must implement**:
- Load implementations from impls.yaml into associative arrays
- Expand filter strings using `expand_filter_string()`
- Generate test combinations (test-type-specific logic)
- Apply filtering using `matches_select()` and `should_ignore()`
- Cache test matrix using `compute_cache_key()`, `check_and_load_cache()`, `save_to_cache()`

**Output**: test-matrix.yaml

#### 3. Image Builder: `<test>/lib/build-images.sh` (~100 lines)

**Purpose**: Build Docker images for all implementations

**Must implement**:
- Parse implementation filter
- For each implementation in impls.yaml:
  - Generate build YAML configuration
  - Call `bash ../lib/build-single-image.sh <yaml>`
- Report build results

**Uses**: Common build-single-image.sh, lib-image-building.sh

#### 4. Single Test Runner: `<test>/lib/run-single-test.sh` (~150 lines)

**Purpose**: Execute a single test by index

**Must implement**:
- Extract test details from test-matrix.yaml using index
- Start Docker containers (test-type-specific setup)
- Wait for test completion
- Capture results (status, duration, metrics)
- Append to results file with file locking (flock)

#### 5. Dashboard Generator: `<test>/lib/generate-dashboard.sh` (~200 lines)

**Purpose**: Generate results visualizations from results.yaml

**Must implement**:
- Read results.yaml
- Generate results.md (summary + visualizations)
- Generate LATEST\_TEST\_RESULTS.md (detailed tables)
- Generate results.html (optional, if pandoc available)

**Output**: results.md, LATEST\_TEST\_RESULTS.md, results.html

#### 6. Snapshot Creator: `<test>/lib/create-snapshot.sh` (~120 lines)

**Purpose**: Create self-contained snapshot of test run

**Must implement** (using common libraries):
```bash
source ../../lib/lib-snapshot-creation.sh
source ../../lib/lib-github-snapshots.sh
source ../../lib/lib-snapshot-rerun.sh
source ../../lib/lib-snapshot-images.sh

# Validate, create structure, copy files
validate_snapshot_inputs()
create_snapshot_directory()
copy_config_files()
copy_all_scripts()
copy_github_sources_to_snapshot()

# Save images (test-type-specific naming)
for impl in required_impls; do
    save_docker_image "<test-type>-<impl>" "$SNAPSHOT_DIR/docker-images"
done

# Generate re-run.sh with test-type-specific options
declare -A original_options
original_options[test_select]="${TEST_SELECT:-}"
# ... set all options ...
generate_rerun_script "$SNAPSHOT_DIR" "<test-type>" "$test_pass" original_options

# Finalize
create_settings_yaml()
generate_snapshot_readme()
validate_snapshot_complete()
```

### Required Configuration

#### impls.yaml

Defines implementations to test:

```yaml
test-aliases:
  - alias: "myalias"
    value: "impl1|impl2"

implementations:
  - id: impl-v1.0
    source:
      type: github
      repo: org/repo
      commit: <full-sha>
      dockerfile: path/to/Dockerfile
      requiresSubmodules: false  # or true
    transports: [tcp, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

### Code Breakdown

**Test-specific code** (must write): ~850 lines
- Main orchestrator: ~300 lines
- Test matrix logic: ~200 lines
- Test execution: ~150 lines
- Dashboard generation: ~200 lines

**Common code** (reused): ~2,500 lines
- Filtering: ~750 lines (lib-filter-engine.sh, lib-test-filtering.sh, etc.)
- Building: ~600 lines (lib-image-building.sh, build-single-image.sh, etc.)
- Snapshots: ~1,150 lines (lib-snapshot-*.sh libraries)

**Effective total per suite**: ~850 lines test-specific + shared infrastructure

---

## Common Functions Index

### lib-filter-engine.sh

#### expand\_filter\_string(filter, all\_names\_array)
- **Inputs**:
  - `filter`: Raw filter string (may contain `~alias`, `!value`, `!~alias`)
  - `all_names_array`: Name of array variable with all possible entity names
- **Outputs**: Fully expanded, deduplicated pipe-separated string
- **Description**: Main filter processing function. Recursively expands aliases (supports unlimited nesting), handles inversions (`!value` becomes all non-matching names, `!~alias` expands alias then negates), detects circular alias references, and deduplicates final result.
- **Where**: `lib-filter-engine.sh:108`

#### filter\_names(input\_names, all\_names, select\_filter, ignore\_filter)
- **Inputs**:
  - `input_names`: Array variable name with names to filter
  - `all_names`: Array variable name with all possible names
  - `select_filter`: Raw SELECT filter (may have aliases)
  - `ignore_filter`: Raw IGNORE filter (may have aliases)
- **Outputs**: Filtered names, one per line
- **Description**: Implements two-step filtering pattern. Applies select filter to input names to get selected set, then applies ignore filter to selected set (not to all names). This ensures correct filtering semantics where ignore operates on already-selected items.
- **Where**: `lib-filter-engine.sh:217`

#### filter\_matches(name, filter\_string)
- **Inputs**:
  - `name`: Single name to check
  - `filter_string`: Expanded filter string (pipe-separated patterns)
- **Outputs**: Exit code (0=matches, 1=no match)
- **Description**: Generic matching function checking if name contains any pattern in filter. Works for any entity type. Used throughout generate-tests.sh for checking implementations, relays, routers, baselines against filters.
- **Where**: `lib-filter-engine.sh:198`

### lib-github-snapshots.sh

#### copy\_github\_sources\_to\_snapshot(snapshot\_dir, cache\_dir)
- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `cache_dir`: Source cache directory
- **Outputs**: Exit code, prints count of sources copied
- **Description**: Copies GitHub sources to snapshot handling both ZIP archives and git clones. Checks requiresSubmodules flag for each implementation, copies ZIPs to snapshots/ and git clones to git-repos/. Enables snapshot reproducibility for all source types.
- **Where**: `lib-github-snapshots.sh:69`

#### get\_required\_github\_sources()
- **Inputs**: None (reads impls.yaml)
- **Outputs**: TSV: `commit<TAB>repo<TAB>requiresSubmodules`
- **Description**: Lists all GitHub-based implementations with their source requirements. Used to determine which ZIP snapshots or git clones are needed for snapshot creation or validation.
- **Where**: `lib-github-snapshots.sh:9`

#### prepare\_git\_clones\_for\_build(snapshot\_dir, cache\_dir)
- **Inputs**:
  - `snapshot_dir`: Snapshot directory with git-repos/
  - `cache_dir`: Target cache directory
- **Outputs**: None (copies git clones to cache)
- **Description**: Makes git clones from snapshot available to build system by copying to cache directory. Called during snapshot re-run to prepare git clones before image building.
- **Where**: `lib-github-snapshots.sh:125`

#### validate\_github\_sources\_cached(cache\_dir)
- **Inputs**: Cache directory path
- **Outputs**: Exit code (0=all present, 1=missing)
- **Description**: Validates all required GitHub sources are in cache. Checks for ZIP files or git clones based on requiresSubmodules flag. Lists missing sources if validation fails.
- **Where**: `lib-github-snapshots.sh:41`

### lib-image-building.sh

#### build\_from\_github(yaml\_file, output\_filter)
- **Inputs**:
  - `yaml_file`: Build YAML configuration file path
  - `output_filter`: Output mode ("normal" or "quiet")
- **Outputs**: Exit code (0=success)
- **Description**: Builds Docker image from GitHub ZIP snapshot. Downloads ZIP if not cached, extracts to temporary directory, runs docker build with specified context and Dockerfile path, tags image, cleans up.
- **Where**: `lib-image-building.sh:155`

#### build\_from\_github\_with\_submodules(yaml\_file, output\_filter)
- **Inputs**:
  - `yaml_file`: Build YAML configuration file path
  - `output_filter`: Output mode ("normal" or "quiet")
- **Outputs**: Exit code (0=success)
- **Description**: Builds Docker image from git clone with submodules. Clones repository if not cached (using `git clone --recursive`), or uses cached clone, then runs docker build. Ensures all submodules are initialized before building.
- **Where**: `lib-image-building.sh:184`

#### clone\_github\_repo\_with\_submodules(repo, commit, cache\_dir)
- **Inputs**:
  - `repo`: Repository name (e.g., "libp2p/rust-libp2p")
  - `commit`: Full commit SHA
  - `cache_dir`: Cache directory for clone
- **Outputs**: Work directory path (caller must clean up)
- **Description**: Clones repository with git including all submodules recursively. Uses `--depth 1` for efficiency. Caches clone in git-repos/ for reuse. Returns temporary work directory path that caller must clean up.
- **Where**: `lib-image-building.sh:52`

#### download\_github\_snapshot(repo, commit, cache\_dir)
- **Inputs**:
  - `repo`: Repository name
  - `commit`: Full commit SHA
  - `cache_dir`: Cache directory path
- **Outputs**: Path to cached ZIP file
- **Description**: Downloads GitHub archive as ZIP file. Checks cache first using commit SHA as key. Downloads from GitHub if not cached. Stores in `/srv/cache/snapshots/<commit>.zip`.
- **Where**: `lib-image-building.sh:6`

### lib-snapshot-creation.sh

#### validate\_snapshot\_inputs(test\_pass\_dir, cache\_dir)
- **Inputs**:
  - `test_pass_dir`: Test pass directory to validate
  - `cache_dir`: Cache directory to validate
- **Outputs**: Exit code (0=valid, 1=invalid)
- **Description**: Validates all required files exist before snapshot creation. Checks for impls.yaml, test-matrix.yaml, results.yaml. Returns error with clear message if any required file is missing.
- **Where**: `lib-snapshot-creation.sh:9`

#### create\_snapshot\_directory(snapshot\_dir)
- **Inputs**: Snapshot directory path
- **Outputs**: Exit code (0=success, 1=exists)
- **Description**: Creates complete snapshot directory structure with all subdirectories including git-repos/ for implementations with submodules. Returns error if directory already exists to prevent accidental overwriting.
- **Where**: `lib-snapshot-creation.sh:43`

#### copy\_all\_scripts(snapshot\_dir, test\_type)
- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `test_type`: Test type identifier
- **Outputs**: None (copies scripts, makes executable)
- **Description**: Copies both test-specific scripts from lib/ and common libraries from ../lib/ to snapshot. Makes all scripts executable. Ensures snapshot is portable and self-contained.
- **Where**: `lib-snapshot-creation.sh:105`

#### generate\_snapshot\_readme(snapshot\_dir, test\_type, test\_pass, summary\_stats)
- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `test_type`: Type of test
  - `test_pass`: Test pass name
  - `summary_stats`: Summary statistics string
- **Outputs**: Creates README.md file
- **Description**: Generates comprehensive README with test summary, contents listing, re-run instructions, file structure diagram, and requirements. Provides complete documentation for snapshot users.
- **Where**: `lib-snapshot-creation.sh:192`

#### display\_snapshot\_summary(snapshot\_dir)
- **Inputs**: Snapshot directory path
- **Outputs**: Formatted summary to stdout
- **Description**: Calculates and displays snapshot summary including size, file counts for all types (logs, docker-compose, images, ZIPs, git clones), and re-run command. Provides clear information about snapshot contents.
- **Where**: `lib-snapshot-creation.sh:277`

### lib-snapshot-images.sh

#### save\_docker\_image(image\_name, output\_dir)
- **Inputs**:
  - `image_name`: Docker image name
  - `output_dir`: Output directory
- **Outputs**: Exit code, creates .tar.gz file
- **Description**: Saves Docker image using `docker save | gzip`. Creates compressed archive for storage in snapshots. Checks if image exists before attempting save.
- **Where**: `lib-snapshot-images.sh:10`

### lib-snapshot-rerun.sh

#### generate\_rerun\_script(snapshot\_dir, test\_type, test\_pass\_name, original\_options)
- **Inputs**:
  - `snapshot_dir`: Target snapshot directory
  - `test_type`: "transport", "hole-punch", or "perf"
  - `test_pass_name`: Test pass identifier
  - `original_options`: Array name with original run options
- **Outputs**: Creates executable re-run.sh script
- **Description**: Generates complete re-run.sh script with full option support. Embeds default values from original run, creates help text, argument parser, validation, image handling, matrix regeneration logic, and test execution. Enables snapshots to be re-run with same or different options.
- **Where**: `lib-snapshot-rerun.sh:16`

### lib-test-aliases.sh

#### load\_aliases()
- **Inputs**: None (reads impls.yaml from current directory)
- **Outputs**: Populates global ALIASES associative array
- **Description**: Loads test-aliases section from impls.yaml. Required before any alias expansion. Called by all generate-tests.sh scripts to enable `~alias` syntax in filters.
- **Where**: `lib-test-aliases.sh:6`

#### get\_all\_impl\_ids()
- **Inputs**: None (reads impls.yaml)
- **Outputs**: Pipe-separated string of all implementation IDs
- **Description**: Extracts all implementation IDs for use in negation expansion. Used when processing `!~alias` patterns to determine which names are NOT in the alias.
- **Where**: `lib-test-aliases.sh:29`

### lib-test-caching.sh

#### compute\_cache\_key(select, ignore, relay\_select, relay\_ignore, router\_select, router\_ignore, debug)
- **Inputs**: All filter strings (up to 6), debug flag
- **Outputs**: SHA-256 hash (64 characters)
- **Description**: Creates content-based cache key from impls.yaml and parameters. Uses double-pipe delimiter (`||`) between values to prevent collision ambiguity. Returns hash used to check/save test matrix cache.
- **Where**: `lib-test-caching.sh:~8`

#### check\_and\_load\_cache(cache\_key, cache\_dir, output\_dir)
- **Inputs**:
  - `cache_key`: SHA-256 hash
  - `cache_dir`: Cache directory
  - `output_dir`: Output directory
- **Outputs**: Exit code (0=hit, 1=miss)
- **Description**: Checks if cached test matrix exists. If found, copies to output directory and returns 0. Provides 10-100x speedup by avoiding matrix regeneration (~50ms vs ~2-5 seconds).
- **Where**: `lib-test-caching.sh:~20`

#### save\_to\_cache(output\_dir, cache\_key, cache\_dir)
- **Inputs**:
  - `output_dir`: Directory with test-matrix.yaml
  - `cache_key`: SHA-256 hash
  - `cache_dir`: Cache directory
- **Outputs**: None (saves matrix to cache)
- **Description**: Copies test-matrix.yaml to cache using key as filename. Called after matrix generation to enable caching for future runs with same configuration.
- **Where**: `lib-test-caching.sh:~35`

### lib-test-filtering.sh

#### matches\_select(test\_name)
- **Inputs**: Test name string
- **Outputs**: Exit code (0=matches, 1=doesn't match)
- **Description**: Checks if test name matches any pattern in SELECT\_PATTERNS array (populated from expanded filter). Returns true if no patterns defined (include all).
- **Where**: `lib-test-filtering.sh:84`

#### should\_ignore(test\_name)
- **Inputs**: Test name string
- **Outputs**: Exit code (0=ignore, 1=keep)
- **Description**: Checks if test name matches any pattern in IGNORE\_PATTERNS array. Handles inverted patterns by extracting dialer/listener and checking both sides. Returns false if no patterns defined (ignore nothing).
- **Where**: `lib-test-filtering.sh:99`

#### get\_common(list1, list2)
- **Inputs**: Two space-separated lists
- **Outputs**: Space-separated list of common elements
- **Description**: Set intersection operation. Used to find common transports, secure channels, or muxers between two implementations during test matrix generation.
- **Where**: `lib-test-filtering.sh:134`

---

*Last Updated: 2025-12-16*
*Version: 3.0.0 (Complete Restructure)*
