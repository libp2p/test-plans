# syntax=docker/dockerfile:1

FROM golang:1.26-alpine AS builder

WORKDIR /app/

COPY go.mod .
COPY go.sum .
RUN go env -w GOCACHE=/go-cache
RUN --mount=type=cache,target=/go-cache go mod download
COPY main.go .
RUN --mount=type=cache,target=/go-cache CGO_ENABLED=0 go build -o /hole-punch-client .

FROM alpine
WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apk apk add bind-tools jq curl tcpdump iproute2-tc
COPY --from=builder /hole-punch-client /usr/bin/hole-punch-client
