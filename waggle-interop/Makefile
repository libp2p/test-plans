# Default target
all: binaries

binaries:
	cd rust-libp2p && cargo build

# Clean all generated shadow simulation files
clean:
	rm -rf shadow-outputs || true
	rm plots/* || true

test:
	# Testing waggle dissemination
	@echo "Testing waggle"
	@uv run run.py --node_count 8 --composition rust --scenario "waggle" && uv run checks/dissemination.py latest --count 1

.PHONY: binaries all clean test
