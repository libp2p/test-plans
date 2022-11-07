FROM nimlang/nim:alpine as builder

RUN nimble install -y "https://github.com/status-im/testground-nim-sdk@#c282ff68c08ef85a7ca011e077e3e69eb1a6edec"
RUN nimble install -y "libp2p"
FROM builder

ARG PLAN_PATH="./"
COPY ./plan/${PLAN_PATH} ./plan
RUN cd plan && nimble install -dy && nim c -d:chronicles_log_level=NOTICE main.nim

ENTRYPOINT ["plan/main"]
