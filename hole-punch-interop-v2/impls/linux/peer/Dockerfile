# Linux Peer for Network Topology Testing
# Combined dialer and listener using ROLE environment variable

FROM debian:trixie-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    redis-tools \
    bash \
    iproute2 \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Copy peer script
COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/run.sh"]
