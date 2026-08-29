# py-libp2p perf (test-plans)

This directory implements the `perf` executable used by the perf benchmark runner (CLI flags + JSON on stdout; see [`perf/README.md`](../../README.md)). It is **not** the unified-testing harness in the py-libp2p repo ([`interop/perf/perf_test.py`](https://github.com/libp2p/py-libp2p/blob/main/interop/perf/perf_test.py), Redis/YAML): that flow does not match this runner’s contract.

## Build

```bash
make          # downloads pinned py-libp2p, creates .venv, installs libp2p
```

Requires `python3.12` (or set `PYTHON_FOR_VENV`, e.g. `python3.11`) so dependencies such as `coincurve` install cleanly.

## Pinned `libp2p` revision

The `commitSha` in [`Makefile`](./Makefile) selects the GitHub archive used for `pip install`. It is currently aligned with [PR #1258](https://github.com/libp2p/py-libp2p/pull/1258) (yamux receive-window and related perf fixes). After that PR merges into `main`, update the pin to a stable `main` commit.

## Implementation notes

- **`perf_cli.py`** uses `PerfService(..., {"write_block_size": 65500})` so writes stay under Noise’s **65535-byte** frame limit; the library default block size can break runner-style upload throughput.
- **Server:** listens on **TCP** (Noise + Yamux) and **QUIC** on the same port pattern (two internal listeners), with the same deterministic peer id as the Go reference perf binary.
- **QUIC client — half-close:** `NetStream.close_write()` in py-libp2p calls `muxed_stream.close()`, which on `QUICStream` closes *both* halves of the stream; the client then cannot read the download phase. `perf_cli.py` patches `NetStream.close_write` to call `close_write()` on the muxed stream when available (upstream: `libp2p/network/stream/net_stream.py`).
- **QUIC client — identify:** `BasicHost` schedules background identify only for QUIC dialers, which opens a second stream on the same connection as perf. The peerstore is seeded with a cached “safe” protocol so identify is skipped (same effect as `BasicHost._has_cached_protocols`).
- **QUIC — aioquic flow limits:** aioquic defaults `QuicConfiguration.max_data` / `max_stream_data` to **1 MiB**. py-libp2p’s `QUICTransportConfig.CONNECTION_FLOW_CONTROL_WINDOW` / `STREAM_FLOW_CONTROL_WINDOW` are not applied to those fields. `perf_cli.py` wraps `create_server_config_from_base` / `create_client_config_from_base` in **both** `libp2p.transport.quic.utils` and `libp2p.transport.quic.transport` (the transport module re-imports the names, so patching only `utils` is not enough) and sets `max_data` / `max_stream_data` from the transport config. **`QUICTransportConfig`** is also passed into `new_host` for QUIC server and client with larger windows and interop-style timeouts.
- **Throughput asymmetry:** With the above, **QUIC upload** in long `timeout …` runs is typically in the same ballpark as TCP on loopback; **QUIC download** (server → client) may still be much lower than TCP in local tests — remaining limits likely involve py-libp2p/aioquic receive scheduling rather than the 1 MiB defaults alone (bumping `max_data` further did not change download totals in quick A/B tests).
- **Runner matrix:** [`runner/versionsInput.json`](../../runner/versionsInput.json) includes **`tcp`** and **`quic-v1`** for this implementation.

## Smoke (local)

```bash
./perf --run-server --server-address 127.0.0.1:4001 &
./perf --server-address 127.0.0.1:4001 --transport tcp --upload-bytes 4096 --download-bytes 4096
./perf --server-address 127.0.0.1:4001 --transport quic-v1 --upload-bytes 4096 --download-bytes 4096
```
