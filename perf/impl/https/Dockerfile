# Build Go Binary
FROM golang:1.20-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN go build -o perf .

FROM alpine

COPY --from=builder /app/perf /app/perf

ENTRYPOINT [ "/app/perf" ]