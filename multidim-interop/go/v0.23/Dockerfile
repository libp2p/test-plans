# syntax=docker/dockerfile:1

FROM golang:1.19-alpine AS builder

WORKDIR /app

COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY *.go ./

RUN go build -o /testplan

FROM alpine:3.17
COPY --from=builder /testplan /testplan

ENTRYPOINT [ "/testplan"]
