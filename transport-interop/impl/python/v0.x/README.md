
Here is a concise guide to running the **transport interop** tests in this repo.

The **`ping_test.py`** script is maintained in the **py-libp2p** repository at [`interop/transport/ping_test.py`](https://github.com/libp2p/py-libp2p/tree/main/interop/transport/ping_test.py). This directory copies it for the Docker build (same behavior as pinning a py-libp2p commit); avoid editing the copy here in isolation—change upstream and sync.

## Prerequisites

- **Docker** and **Docker Compose** (the runner shells out to `docker compose`).
- **Node.js** (use a current LTS; CI uses `lts/*`).
- Enough disk/CPU: the full matrix is large and will **build or pull** many images.

## Run the suite

For **`python-v0.x`**, build or retag the Docker image first so Compose does not try to pull the content-hash tag from GHCR (see “Using a locally built Python image” below). From `transport-interop`:

```bash
make -C impl/python/v0.x
npm run build:python-image -- --tag-only   # or: npm run build:python-image
```

(`npm run build:python-image` runs `impl/python/v0.x/build-local-python-image.sh`.)

From the repo root:

```bash
cd transport-interop
npm ci
npm run test
```

That runs `ts-node src/compose-stdout-helper.ts` then `ts-node testplans.ts`, which generates compose specs from `versions.ts`, runs each scenario, and writes **`results.csv`** in `transport-interop/`.

## Useful options

**Parallelism** (default is 1 worker):

```bash
WORKER_COUNT=4 npm run test
```

**Run only some tests** (names are substrings; pipe-separated):

```bash
npm run test -- --name-filter="go-v0.48 x rust-v0.56"
```

**Skip tests** whose names match any pipe-separated substring:

```bash
npm run test -- --name-ignore="jvm-v1.2 x zig|zig-v0.0.1 x jvm"
```

**Shard the matrix** (same idea as CI: both must be set):

```bash
SHARD_COUNT=4 SHARD_INDEX=0 npm run test   # first of 4 shards
```

**Inspect generated Compose only** (no Docker runs):

```bash
npm run test -- --emit-only
```

**Verbose**:

```bash
npm run test -- --verbose
```

**Per-test Docker timeout** (seconds; default is 600 if unset—see `compose-runner.ts`):

```bash
TIMEOUT=900 npm run test
```

## After the run

- **`results.csv`**: pass/fail per test name.
- Optional HTML-ish summary for the dashboard:

```bash
npm run renderResults
```

(Produces output you can redirect to a file; CI uses `npm run renderResults > ./dashboard.md`.)

## Images and first-time local runs

Each implementation under `transport-interop/impl/<lang>/<version>/` has an **`image.json`** with the Docker image id. Those are usually filled when images are built or restored from cache. If a test fails because an image is missing, build that implementation from its directory (often **`make`**) as in `transport-interop/README.md` under “Running Locally.”

### Using a locally built Python image with the default matrix

Interop tests load **`versionsInput.json`** (merged with optional, gitignored `versionsInput.local.json`). A local override that replaces the whole `python-v0.x` entry also replaces transports and secure channels, which narrows the matrix. To keep the **default** capabilities from `versionsInput.json` while still using your own image:

1. From `transport-interop`, prepare sources: `make -C impl/python/v0.x`
2. Tag the image so its name matches what `versions.ts` computes for the GHCR reference (content-hash tag). From **`impl/python/v0.x`**:

   ```bash
   ./build-local-python-image.sh --tag-only
   ```

   Or build and tag in one step:

   ```bash
   ./build-local-python-image.sh
   ```

   From `transport-interop` you can use `npm run build:python-image` instead (same script).
Rule of thumb: after editing anything under impl/python/v0.x, run npm run build:python-image again before npm run test, so the local tag always matches the latest hash.
3. Run tests as usual (`npm run test`). Do **not** rely on `versionsInput.local.json` for this workflow; remove it if you added it earlier.

The script uses the same cache-key algorithm as `.github/scripts/compute-cache-key.mjs` and `versions.ts`, so the tag stays in sync when you change files under `impl/python/v0.x`.

---

**Summary:** `cd transport-interop && npm ci && npm run test`, with Docker running. Use `WORKER_COUNT`, `--name-filter`, `--name-ignore`, and `SHARD_*` when you do not want the full matrix or want faster feedback.
