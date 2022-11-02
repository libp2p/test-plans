FROM nimlang/nim:alpine as builder

RUN nimble install -y "https://github.com/status-im/testground-nim-sdk@#9fba8111179c2ace7a2b595d8ed8cb10f0bf9c21"
RUN nimble install -y "libp2p"
FROM builder

COPY . .
RUN cd plan && nimble install -dy && nim c -d:chronicles_log_level=NOTICE main.nim

ENTRYPOINT ["plan/main"]
