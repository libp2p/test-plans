# syntax=docker/dockerfile:1.5-labs

FROM --platform=$BUILDPLATFORM rust:1.72.0 as builder

ARG BUILDPLATFORM

WORKDIR /workspace
COPY . /workspace
COPY build.sh /build.sh
RUN chmod +x /build.sh && /build.sh ${BUILDPLATFORM}

FROM alpine:3
COPY --from=builder /usr/local/bin/relay /usr/bin/relay
RUN --mount=type=cache,target=/var/cache/apk apk add iproute2-tc

ENV RUST_BACKTRACE=1

CMD ["/usr/bin/relay"]
