FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    redis-tools \
    build-essential \
    cmake \
    pkg-config \
    libgmp-dev \
    git \
    patch \
    && rm -rf /var/lib/apt/lists/*

# Copy the py-libp2p-${commitSha} folder so we can use it as a local dependency
COPY py-libp2p-* /app/py-libp2p

# Copy pyproject.toml and install Python dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir -e . && \
    # Fix multihash conflict: multiaddr depends on py-multihash, but py-libp2p needs pymultihash
    # Uninstall py-multihash and reinstall pymultihash to ensure pymultihash's module is used
    pip uninstall -y py-multihash && \
    pip install --no-cache-dir --force-reinstall pymultihash>=0.8.2

# Apply PR #1034 Yamux fix for Rust interop
# This patch reads data accompanying SYN and ACK frames, which Rust sends
# See: https://github.com/libp2p/py-libp2p/pull/1034
COPY yamux-rust-fix.patch /tmp/yamux-rust-fix.patch
RUN YAMUX_PATH=$(python -c "import libp2p.stream_muxer.yamux.yamux; import os; print(os.path.dirname(libp2p.stream_muxer.yamux.yamux.__file__))") && \
    cd "$YAMUX_PATH" && \
    patch -p0 < /tmp/yamux-rust-fix.patch && \
    echo "Yamux patch applied successfully" || \
    (echo "Warning: Patch may have already been applied or failed - checking..." && \
     grep -q "Read.*bytes with SYN" yamux.py && echo "Patch already applied" || exit 1)

# Copy the ping test implementation
COPY ping_test.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV CI=true

# Set the entrypoint to run the ping test
ENTRYPOINT ["python", "ping_test.py"]
