# Default target
all: binaries

NIM_LIBP2P_COMMIT = 19d6127890c80bc65323c6f5e4ef03d868378d0d
nim-libp2p/gossipsub-bin:
	@echo "Building nim-libp2p from commit: $(NIM_LIBP2P_COMMIT)"
	# Clone nim-libp2p (if not already present) and build gossipsub binary
	@if [ ! -d "nim-libp2p-src" ]; then \
		git clone https://github.com/vacp2p/nim-libp2p.git nim-libp2p-src && \
		cd nim-libp2p-src && git checkout $(NIM_LIBP2P_COMMIT); \
	fi
	@mkdir -p nim-libp2p
	cd nim-libp2p-src && nimble install_pinned
	cd nim-libp2p-src && nim c -d:release \
		--skipProjCfg --skipParentCfg \
		--NimblePath:./nimbledeps/pkgs2 \
		-p:. --mm:refc \
		-d:chronicles_colors=None \
		-d:chronicles_log_level=TRACE \
		-d:chronicles_default_output_device=stderr \
		--threads:on \
		-o:$(CURDIR)/nim-libp2p/gossipsub-bin \
		./interop/gossipsub/peer.nim

binaries: nim-libp2p/gossipsub-bin
	cd go-libp2p && go build -linkshared -o gossipsub-bin
	cd rust-libp2p && cargo build

# Clean all generated shadow simulation files
clean:
	rm -rf shadow-outputs || true
	rm -rf nim-libp2p-src || true
	rm -f nim-libp2p/gossipsub-bin || true
	rm plots/* || true

test:
	# Testing partial messages
	@echo "Testing partial messages (rust-and-go)"
	@uv run run.py --node_count 32 --composition "rust-and-go" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages (nim-and-go)"
	@uv run run.py --node_count 32 --composition "nim-and-go" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages (nim-and-rust)"
	@uv run run.py --node_count 32 --composition "nim-and-rust" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain (rust-and-go)"
	@uv run run.py --node_count 8 --composition "rust-and-go" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing partial messages chain (nim-and-go)"
	@uv run run.py --node_count 8 --composition "nim-and-go" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing partial messages chain (nim-and-rust)"
	@uv run run.py --node_count 8 --composition "nim-and-rust" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout (rust-and-go)"
	uv run run.py --node_count 8 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

	@echo "Testing fanout (nim-and-go)"
	uv run run.py --node_count 8 --composition "nim-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition "nim-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition "nim-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition "nim-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

	@echo "Testing fanout (nim-and-rust)"
	uv run run.py --node_count 8 --composition "nim-and-rust" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition "nim-and-rust" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition "nim-and-rust" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition "nim-and-rust" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

test-go:
	# Testing partial messages
	@echo "Testing partial messages"
	@uv run run.py --node_count 8 --composition "all-go" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain"
	@uv run run.py --node_count 8 --composition "all-go" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout"
	@uv run run.py --node_count 2 --composition "all-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/


test-rust-only:
	# Testing partial messages
	@echo "Testing partial messages"
	@uv run run.py --node_count 8 --composition "all-rust" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain"
	@uv run run.py --node_count 8 --composition "all-rust" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout"
	@uv run run.py --node_count 2 --composition "all-rust" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/



.PHONY: binaries all clean test
