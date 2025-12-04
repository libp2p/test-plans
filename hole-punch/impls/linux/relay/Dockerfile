# Netcat-based Relay for Network Topology Testing
# Simple TCP relay for validating NAT routing and network setup

FROM debian:trixie-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    redis-tools \
    bash \
    iproute2 \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy relay script
COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/run.sh"]
