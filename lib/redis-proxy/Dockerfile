FROM rust:1-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY Cargo.toml Cargo.lock* ./
COPY src/ src/
RUN cargo build --release --target x86_64-unknown-linux-musl 2>/dev/null || \
    cargo build --release
RUN cp target/x86_64-unknown-linux-musl/release/redis-proxy /redis-proxy 2>/dev/null || \
    cp target/release/redis-proxy /redis-proxy

FROM scratch
COPY --from=builder /redis-proxy /redis-proxy
EXPOSE 6379
ENTRYPOINT ["/redis-proxy"]
