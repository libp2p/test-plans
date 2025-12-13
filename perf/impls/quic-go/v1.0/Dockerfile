FROM golang:1.22-alpine AS builder

WORKDIR /workspace

COPY main.go go.mod go.sum* ./

RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o perf-quic .

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /workspace/perf-quic .

ENTRYPOINT ["/app/perf-quic"]
