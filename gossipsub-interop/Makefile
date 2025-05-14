# Default target
all: run

# Clean all generated shadow simulation files
clean:
	rm -rf *.data || true
	rm plots/* || true

binaries:
	cd gossipsub-v0.13.1 && go build -linkshared -o gossipsub-bin
	cd rust-libp2p && cargo build

# Run the shadow simulation
run:
	uv run run.py

.PHONY: binaries all run clean
