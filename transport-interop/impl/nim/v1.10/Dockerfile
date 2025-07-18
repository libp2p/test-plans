FROM nimlang/nim:1.6.16 AS builder

WORKDIR /app

COPY nim-libp2p nim-libp2p

RUN --mount=type=cache,target=/var/cache/apt apt-get update && apt-get install -y libssl-dev

RUN \
  cd nim-libp2p && \
  nimble install_pinned

RUN \
  cd nim-libp2p && \
  nimble install "redis@#b341fe240dbf11c544011dd0e033d3c3acca56af"

COPY main.nim main.nim
RUN \
  nim c --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:libp2p_quic_support -d:chronicles_log_level=WARN --threads:off main.nim

ENTRYPOINT ["/app/main"]
