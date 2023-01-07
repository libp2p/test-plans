# syntax=docker/dockerfile:1

FROM golang:1.19-alpine

WORKDIR /app

COPY go.mod ./
COPY go.sum ./
RUN go mod download

RUN apk add iproute2-tc tcpdump iputils

COPY *.go ./

RUN go build -o /testplan

EXPOSE 6060
ENTRYPOINT [ "/bin/sh", "-c", "mkdir -p /results && \
  tc qdisc add dev eth0 root netem delay 50ms && \
  tcpdump -i eth0 -s 65535 -U -w /results/dump.pcap & /testplan" ]
