.PHONY: all build clean run-server-tcp run-server-quic run-client-tcp run-client-quic

# Default target
all: build

# Build the .NET project
build:
	dotnet build

# Clean build artifacts
clean:
	dotnet clean
	rm -rf bin/ obj/

# Run server with TCP transport
run-server-tcp:
	dotnet run -- -run-server -server-address 127.0.0.1:8080 -transport tcp

# Run server with QUIC transport
run-server-quic:
	dotnet run -- -run-server -server-address 127.0.0.1:8080 -transport quic

# Run client with TCP transport (100MB upload/download)
run-client-tcp:
	dotnet run -- -server-address 127.0.0.1:8080 -transport tcp -upload-bytes 104857600 -download-bytes 104857600

# Run client with QUIC transport (100MB upload/download)
run-client-quic:
	dotnet run -- -server-address 127.0.0.1:8080 -transport quic -upload-bytes 104857600 -download-bytes 104857600

# Run client with TCP transport (1GB upload/download for performance testing)
run-client-tcp-large:
	dotnet run -- -server-address 127.0.0.1:8080 -transport tcp -upload-bytes 1073741824 -download-bytes 1073741824

# Run client with QUIC transport (1GB upload/download for performance testing)
run-client-quic-large:
	dotnet run -- -server-address 127.0.0.1:8080 -transport quic -upload-bytes 1073741824 -download-bytes 1073741824