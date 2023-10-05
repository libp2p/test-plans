ARG NimVersion="1.6.10"
FROM nimlang/nim:${NimVersion}-alpine as builder

WORKDIR /app

COPY nim-libp2p nim-libp2p

RUN \
  cd nim-libp2p && \
  nimble install_pinned

RUN \
  cd nim-libp2p && \
  nimble install "redis@#b341fe240dbf11c544011dd0e033d3c3acca56af"

COPY main.nim main.nim
RUN \
  nim c --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:chronicles_log_level=WARN --threads:off main.nim

ENTRYPOINT ["/app/main"]
