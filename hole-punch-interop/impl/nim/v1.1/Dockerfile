# syntax=docker/dockerfile:1.5-labs
FROM nimlang/nim:1.6.14 as builder

# Run with access to the target cache to speed up builds
WORKDIR /workspace

COPY nim-libp2p nim-libp2p

# Cache the nimcache and nimble directories to speed up builds
RUN cd nim-libp2p && nimble install_pinned && nimble install redis -y

COPY ../hole_punching.nim nim-libp2p/hole_punching.nim

RUN --mount=type=cache,target=/root/.nimble \
    --mount=type=cache,target=/root/.cache/nim \
    cd nim-libp2p && nim c --nimcache:root/.cache/nim -d:chronicles_log_level=DEBUG -d:chronicles_default_output_device=stderr --threads:off -d:release -o:hole-punching-tests hole_punching.nim

RUN ls -la /root/.cache/nim

RUN echo $(dpkg --print-architecture)

FROM --platform=linux/amd64 debian:bookworm-slim
RUN --mount=type=cache,target=/var/cache/apt apt-get update && apt-get install -y dnsutils jq curl tcpdump iproute2
COPY --from=builder /workspace/nim-libp2p/hole-punching-tests /usr/bin/hole-punch-client
ENV RUST_BACKTRACE=1
