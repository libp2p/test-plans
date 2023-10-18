# syntax=docker/dockerfile:1.5-labs

FROM --platform=$BUILDPLATFORM rust:1.72.0 as builder

ARG BUILDPLATFORM

# Copy the setup.sh script into the image
COPY setRustTarget.sh /setRustTarget.sh

RUN chmod +x /setRustTarget.sh && /setRustTarget.sh ${BUILDPLATFORM}

# Conditionally install musl-tools if targeting musl
RUN --mount=type=cache,target=/var/cache/apt \
    . /etc/environment && \
    apt-get update && \
    if [[ "${RUST_TARGET}" == *"-musl"* ]]; then \
        apt-get install -y musl-dev musl-tools; \
    fi

# Run with access to the target cache to speed up builds
WORKDIR /workspace
ADD . .
RUN --mount=type=cache,target=./target \
    --mount=type=cache,target=/usr/local/cargo/registry \
    . /etc/environment && \
    cargo build --release --package relay --target ${RUST_TARGET}

RUN --mount=type=cache,target=./target \
    . /etc/environment && \
    mv ./target/${RUST_TARGET}/release/relay /usr/local/bin/relay

FROM alpine:3
COPY --from=builder /usr/local/bin/relay /usr/bin/relay
RUN --mount=type=cache,target=/var/cache/apk apk add iproute2-tc

ENV RUST_BACKTRACE=1

CMD ["/usr/bin/relay"]
