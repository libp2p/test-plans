FROM nimlang/nim:2.2.4-ubuntu-regular AS builder

WORKDIR /app

COPY nim-libp2p-* nim-libp2p

RUN --mount=type=cache,target=/var/cache/apt apt-get update && apt-get install -y libssl-dev

RUN \
  cd nim-libp2p && \
  nimble install_pinned

RUN \
  cd nim-libp2p && \
  nimble install redis@0.5.0

COPY main.nim main.nim
RUN \
  nim c --NimblePath:nim-libp2p/nimbledeps/pkgs2 -p:nim-libp2p -d:libp2p_quic_support -d:chronicles_log_level=WARN --threads:off main.nim

ENTRYPOINT ["/app/main"]
