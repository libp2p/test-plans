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

# Copy pyproject.toml and install Python dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir -e . && \
    # Fix multihash conflict: multiaddr depends on py-multihash, but py-libp2p needs pymultihash
    # Uninstall py-multihash and reinstall pymultihash to ensure pymultihash's module is used
    pip uninstall -y py-multihash && \
    pip install --no-cache-dir --force-reinstall pymultihash>=0.8.2

# Copy the ping test implementation
COPY ping_test.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV CI=true

# Set the entrypoint to run the ping test
ENTRYPOINT ["python", "ping_test.py"]
