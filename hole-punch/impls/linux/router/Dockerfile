# Linux NAT Router for Hole Punch Interop Tests
# Provides NAT functionality between LAN and WAN networks using iptables

FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    iptables \
    iproute2 \
    tcpdump

# Copy NAT configuration script
COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/run.sh"]
