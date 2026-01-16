FROM golang:1.22-alpine AS builder

WORKDIR /workspace

# Install dependencies
RUN apk add --no-cache git make

# Clone go-libp2p perf implementation
# Using the libp2p/test-plans perf implementation as a base
RUN git clone --depth 1 https://github.com/libp2p/go-libp2p.git /tmp/go-libp2p || true

# Create perf implementation
COPY main.go go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Build the perf binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o perf .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /workspace/perf .

ENTRYPOINT ["/app/perf"]
