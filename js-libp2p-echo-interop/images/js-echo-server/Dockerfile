# JS-libp2p Echo Server Dockerfile
# Multi-stage build for optimized production image
# Implements proper output hygiene: stdout for multiaddr, stderr for diagnostics

# Build stage
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies (including dev dependencies for potential testing)
RUN npm ci && npm cache clean --force

# Production stage
FROM node:20-alpine AS production

# Install dumb-init for proper signal handling and process management
# Also install bash and redis-cli for health checks
RUN apk add --no-cache dumb-init bash redis

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy dependencies from builder stage
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application source
COPY --chown=nodejs:nodejs src ./src
COPY --chown=nodejs:nodejs package.json ./

# Create lib directory and copy health check script
RUN mkdir -p ./lib
COPY --chown=nodejs:nodejs health-check.sh ./lib/health-check.sh

# Switch to non-root user
USER nodejs

# Expose port (will be dynamically assigned at runtime)
EXPOSE 0

# Health check to verify container readiness using enhanced health check script
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD bash /app/lib/health-check.sh js-server || exit 1

# Environment variables for protocol configuration
# These support the multidimensional interop testing framework
ENV NODE_ENV=production \
    TRANSPORT=tcp \
    SECURITY=noise \
    MUXER=yamux \
    IS_DIALER=false \
    HOST=0.0.0.0 \
    PORT=0 \
    REDIS_ADDR=redis://redis:6379

# Labels for container metadata and traceability
LABEL maintainer="libp2p team" \
      description="JS-libp2p Echo Server for interoperability tests" \
      version="1.0.0" \
      protocol="/echo/1.0.0" \
      output.hygiene="stdout:multiaddr,stderr:diagnostics"

# Use dumb-init to handle signals properly and ensure clean shutdown
ENTRYPOINT ["dumb-init", "--"]

# Start the application with proper output hygiene
# stdout: multiaddr output for test coordination
# stderr: diagnostic and debug information
CMD ["node", "src/index.js"]