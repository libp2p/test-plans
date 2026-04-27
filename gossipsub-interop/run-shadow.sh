#!/usr/bin/env bash
# Run a Shadow gossipsub experiment inside the Docker container.
#
# Expected mounts:
#   /work        → gossipsub-interop directory (this repo)
#   /eth-p2p-z   → eth-p2p-z source directory
#   /root/.cache/zig  → host Zig global package cache (optional, speeds up build)
#
# Usage:
#   bash /work/run-shadow.sh [run.py args...]
# Example:
#   bash /work/run-shadow.sh --node_count 4 --composition all-zig --scenario subnet-blob-msg
set -euo pipefail

echo "==> Building gossipsub-bin for linux/x86_64..."
# -Dcpu overrides the auto-detected CPU (e.g. 'athlon-xp' under Rosetta/QEMU
# which newer LLVM doesn't recognise) while keeping native mode so Zig still
# uses system headers (needed for zlib.h etc).
zig build \
    --build-file /eth-p2p-z/build.zig \
    --prefix /work/zig-libp2p/zig-out \
    -Doptimize=ReleaseFast \
    -Dcpu=x86_64

cp /work/zig-libp2p/zig-out/bin/gossipsub-bin /work/zig-libp2p/gossipsub-bin
echo "    gossipsub-bin: $(du -sh /work/zig-libp2p/gossipsub-bin | cut -f1)"

echo "==> Running Shadow experiment..."
uv run /work/run.py --skip_build true "$@"
