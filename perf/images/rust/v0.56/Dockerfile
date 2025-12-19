FROM rust:alpine AS builder

WORKDIR /workspace

# Install all required dependencies for rust-libp2p
RUN apk add --no-cache \
    musl-dev \
    protobuf-dev \
    cmake \
    perl \
    pkgconfig \
    openssl-dev

# Copy manifests first for dependency caching
COPY Cargo.toml ./
COPY Cargo.lock* ./

# Create dummy source for dependency fetch
RUN mkdir -p src && \
    echo "fn main() {}" > src/main.rs

# Fetch dependencies (this layer will be cached)
RUN cargo fetch

# Remove dummy source
RUN rm -rf src

# Copy real source
COPY src/ ./src/

# Build in release mode
RUN cargo build --release

# Final stage
FROM alpine:latest

RUN apk --no-cache add \
    ca-certificates \
    libgcc

WORKDIR /app

COPY --from=builder /workspace/target/release/perf-rust .

ENTRYPOINT ["/app/perf-rust"]
