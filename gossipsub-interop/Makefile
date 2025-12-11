# Default target
all: binaries

binaries:
	cd go-libp2p && go build -linkshared -o gossipsub-bin
	cd rust-libp2p && cargo build
	cd py-libp2p && chmod +x main.py

# Clean all generated shadow simulation files
clean:
	rm -rf *.data || true
	rm plots/* || true

.PHONY: binaries all clean
