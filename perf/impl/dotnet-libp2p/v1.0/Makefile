.PHONY: all build clean run-server-tcp run-server-quic run-client-tcp run-client-quic

# Default target
all: perf

# Build the .NET project using Docker (like Go implementation)
perf: PerfBenchmarks.csproj Program.cs PerfProtocol.cs
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp mcr.microsoft.com/dotnet/sdk:9.0 dotnet build -c Release -o ./bin/Release/net9.0
	cp bin/Release/net9.0/PerfBenchmarks perf

# Clean build artifacts
clean:
	rm -rf bin/ obj/ perf .cache

# Run server with TCP transport
run-server-tcp:
	./perf --run-server --server-address 127.0.0.1:8080 --transport tcp

# Run server with QUIC transport
run-server-quic:
	./perf --run-server --server-address 127.0.0.1:8080 --transport quic

# Run client with TCP transport (100MB upload/download)
run-client-tcp:
	./perf --server-address 127.0.0.1:8080 --transport tcp --upload-bytes 104857600 --download-bytes 104857600

# Run client with QUIC transport (100MB upload/download)
run-client-quic:
	./perf --server-address 127.0.0.1:8080 --transport quic --upload-bytes 104857600 --download-bytes 104857600

# Run client with TCP transport (1GB upload/download for performance testing)
run-client-tcp-large:
	./perf --server-address 127.0.0.1:8080 --transport tcp --upload-bytes 1073741824 --download-bytes 1073741824

# Run client with QUIC transport (1GB upload/download for performance testing)
run-client-quic-large:
	./perf --server-address 127.0.0.1:8080 --transport quic --upload-bytes 1073741824 --download-bytes 1073741824