# syntax=docker/dockerfile:1.5-labs
FROM rust:1-bookworm AS builder

WORKDIR /workspace

# quinn's crypto backend (aws-lc-rs) needs cmake and a C compiler to build.
RUN apt-get update && apt-get install -y --no-install-recommends cmake clang \
    && rm -rf /var/lib/apt/lists/*

ADD . .

# The target directory is a cache mount, so the binary is copied out within the
# same step to a location that persists into the image.
RUN --mount=type=cache,target=./target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --release --bin autonat-client \
    && cp ./target/release/autonat-client /usr/local/bin/autonat-client

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/local/bin/autonat-client /usr/bin/autonat-client
ENV RUST_BACKTRACE=1
CMD ["/usr/bin/autonat-client"]
