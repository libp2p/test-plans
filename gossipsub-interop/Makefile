# Default target
all: binaries

binaries:
	cd go-libp2p && go build -linkshared -o gossipsub-bin
	cd rust-libp2p && cargo build

go-rust-extensions-interop:
	uv run run.py --nodes go-libp2p/gossipsub-bin rust-libp2p/target/debug/rust-libp2p-gossip --scenario "one-msg"
	uv run verify-extensions-interop.py

# Clean all generated shadow simulation files
clean:
	rm -rf *.data || true
	rm plots/* || true

.PHONY: binaries all clean go-rust-extensions-interop
