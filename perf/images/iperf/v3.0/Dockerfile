FROM debian:13-slim

# Install iperf3, redis-tools for coordination, and utilities for statistics
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iperf3 \
        redis-tools \
        bc \
        jq \
        procps \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Copy run script
WORKDIR /app
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

# Entry point
ENTRYPOINT ["/app/run.sh"]
