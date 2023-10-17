# syntax=docker/dockerfile:1.5-labs

FROM rust:1.72.0 as builder

# Default value if not provided
ARG TARGET_ARCH=x86_64-unknown-linux-musl
RUN rustup target add ${TARGET_ARCH}

# Conditionally install musl-tools if targeting musl
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    if [[ "${TARGET_ARCH}" == *"-musl"* ]]; then \
        apt-get install -y musl-dev musl-tools; \
    fi

# Run with access to the target cache to speed up builds
WORKDIR /workspace
ADD . .
RUN --mount=type=cache,target=./target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    cargo build --release --package relay --target ${TARGET_ARCH}

RUN --mount=type=cache,target=./target \
    mv ./target/${TARGET_ARCH}/release/relay /usr/local/bin/relay

FROM alpine:3
COPY --from=builder /usr/local/bin/relay /usr/bin/relay
RUN --mount=type=cache,target=/var/cache/apk apk add iproute2-tc

ENV RUST_BACKTRACE=1

CMD ["/usr/bin/relay"]
