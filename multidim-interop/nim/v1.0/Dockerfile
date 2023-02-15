ARG NimVersion="latest"
FROM nimlang/nim:${NimVersion}-alpine as builder

WORKDIR /app

COPY main.nimble .
RUN nim -v
RUN nimble install -dy

COPY main.nim .
RUN nim c -d:chronicles_log_level=WARN --threads:off main.nim

ENTRYPOINT ["main"]
