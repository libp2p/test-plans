# Shadow network simulator + Zig build environment
# Runs on linux/amd64 (Shadow requirement).
#
# Uses the pre-built shadowsim/shadow-ci image so we skip the ~1h Shadow
# Rust compilation that was previously needed under QEMU on Apple Silicon.
#
# Build:
#   docker build --platform linux/amd64 -t gossipsub-shadow .
#
# Run (from gossipsub-interop directory):
#   docker run --rm --platform linux/amd64 \
#     -v $(pwd):/work \
#     -v /path/to/eth-p2p-z:/eth-p2p-z \
#     -v $HOME/.cache/zig:/root/.cache/zig \
#     gossipsub-shadow \
#     bash /work/run-shadow.sh --node_count 4 --composition all-zig --scenario subnet-blob-msg

FROM --platform=linux/amd64 shadowsim/shadow-ci:ubuntu-22.04-gcc-release

# ── Extra system libraries needed by the Zig/C build ─────────────────────
# zlib1g-dev: required by lsquic (zlib.h)
RUN apt-get update && apt-get install -y \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── Zig 0.15.2 ────────────────────────────────────────────────────────────
RUN curl -fL https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz \
    | tar -xJ -C /usr/local \
    && ln -s /usr/local/zig-x86_64-linux-0.15.2/zig /usr/local/bin/zig

# ── uv (Python package manager for experiment scripts) ────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /work
