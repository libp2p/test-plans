# Linux NAT Router for Hole Punch Interop Tests
# Provides NAT functionality between LAN and WAN networks using iptables

FROM alpine:3.19

# Install required packages
# Note: Alpine includes BusyBox awk by default, but we install gawk for full functionality
RUN apk add --no-cache \
    bash \
    iptables \
    iproute2 \
    ipcalc \
    gawk \
    tcpdump

# Copy NAT configuration script
COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/run.sh"]
