FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 \
    redis-tools \
    dnsutils \
    curl \
    jq \
    tcpdump \
    build-essential \
    cmake \
    pkg-config \
    libgmp-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY py-libp2p-* /app/py-libp2p

COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

COPY hole_punch_client.py .
COPY hole-punch-client /usr/local/bin/hole-punch-client
RUN chmod +x /usr/local/bin/hole-punch-client

ENV PYTHONUNBUFFERED=1
