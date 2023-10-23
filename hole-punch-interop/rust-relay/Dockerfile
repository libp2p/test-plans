# syntax=docker/dockerfile:1.5-labs
FROM --platform=$BUILDPLATFORM rust:1.72.0 as builder

# Run with access to the target cache to speed up builds
WORKDIR /workspace
ADD . .

RUN --mount=type=cache,target=./target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --release --package relay && \
    mv ./target/release/relay /usr/local/bin/relay

FROM --platform=$TARGETPLATFORM debian:bookworm-slim
COPY --from=builder /usr/local/bin/relay /usr/bin/relay
RUN --mount=type=cache,target=/var/cache/apt apt-get update && apt-get install -y iproute2
ENV RUST_BACKTRACE=1
CMD ["/usr/bin/relay"]
