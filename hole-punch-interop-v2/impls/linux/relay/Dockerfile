# Netcat-based Relay for Network Topology Testing
# Simple TCP relay for validating NAT routing and network setup

FROM debian:trixie-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    python3 \
    redis-tools \
    bash \
    iproute2 \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy relay scripts
COPY run.sh /usr/local/bin/run.sh
COPY relay.py /usr/local/bin/relay.py
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/relay.py

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/run.sh"]
