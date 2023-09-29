FROM golang:1.21 AS builder

COPY . /node
WORKDIR /node
RUN --mount=type=cache,target=/go go mod download
RUN --mount=type=cache,target=/go go build -o node main.go

FROM ubuntu:jammy

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y iproute2 dnsutils tcpdump jq curl

COPY --from=builder /node/node /usr/bin/hole-punch-client
