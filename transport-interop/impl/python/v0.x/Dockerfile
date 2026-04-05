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
    && rm -rf /var/lib/apt/lists/*

# Copy the py-libp2p-${commitSha} folder so we can use it as a local dependency
COPY py-libp2p-* /app/py-libp2p

# Copy pyproject.toml and install Python dependencies
COPY pyproject.toml .
# Keep py-libp2p's multihash stack: libp2p peer IDs require `multihash.encode` (py-multihash).
RUN pip install --no-cache-dir -e .

# Copy the ping test implementation
COPY ping_test.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV CI=true

# test-plans harness (JSON + listenerAddr Redis)
ENTRYPOINT ["python", "ping_test.py", "--test-plans"]
