# Default target
all: binaries

NIM_LIBP2P_COMMIT = 22ab0402cd86f88fba0103f7946311d93e2566cd
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
	cd jvm-libp2p && ./gradlew installDist
	zig build --build-file $(CURDIR)/../../eth-p2p-z/build.zig --prefix $(CURDIR)/zig-libp2p/zig-out -Doptimize=ReleaseFast -Dlibxev-backend=epoll
	cp $(CURDIR)/zig-libp2p/zig-out/bin/gossipsub-bin $(CURDIR)/zig-libp2p/gossipsub-bin

# Clean all generated shadow simulation files
clean:
	rm -rf shadow-outputs || true
	rm -rf nim-libp2p-src || true
	rm -f nim-libp2p/gossipsub-bin || true
	rm latest
	rm plots/* || true

test: test-partial-messages test-subnet-blob

test-partial-messages:
	# Testing partial messages
	@echo "Testing partial messages (rust-and-go)"
	@uv run run.py --node_count 32 --composition rust go --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages (nim-and-go)"
	@uv run run.py --node_count 32 --composition nim go --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages (nim-and-rust)"
	@uv run run.py --node_count 32 --composition nim rust --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain (rust-and-go)"
	@uv run run.py --node_count 8 --composition rust go --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing partial messages chain (nim-and-go)"
	@uv run run.py --node_count 8 --composition nim go --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing partial messages chain (nim-and-rust)"
	@uv run run.py --node_count 8 --composition nim rust --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout (rust-and-go)"
	uv run run.py --node_count 8 --composition rust go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition rust go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition rust go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition rust go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

	@echo "Testing fanout (nim-and-go)"
	uv run run.py --node_count 8 --composition nim go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition nim go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition nim go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition nim go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

	@echo "Testing fanout (nim-and-rust)"
	uv run run.py --node_count 8 --composition nim rust --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition nim rust --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition nim rust --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition nim rust --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

test-subnet-blob:
	# Testing subnet blob scenario
	@echo "Testing subnet blob messages"
	@echo "Testing single implementations"
	uv run run.py --node_count 32 --composition go && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition rust && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition jvm && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition nim && uv run checks/subnet_blob_msg.py latest/

	@echo "Testing impl pairs"
	uv run run.py --node_count 32 --composition rust go && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition jvm go && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition jvm rust && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition nim go && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition nim rust && uv run checks/subnet_blob_msg.py latest/
	uv run run.py --node_count 32 --composition nim jvm && uv run checks/subnet_blob_msg.py latest/

	@echo "Testing all"
	uv run run.py --node_count 32 --composition go rust jvm nim && uv run checks/subnet_blob_msg.py latest/

test-go:
	# Testing partial messages
	@echo "Testing partial messages"
	@uv run run.py --node_count 8 --composition go --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain"
	@uv run run.py --node_count 8 --composition go --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout"
	@uv run run.py --node_count 2 --composition go --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/


test-rust-only:
	# Testing partial messages
	@echo "Testing partial messages"
	@uv run run.py --node_count 8 --composition rust --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain"
	@uv run run.py --node_count 8 --composition rust --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout"
	@uv run run.py --node_count 2 --composition rust --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/


test-zig:
	# Testing all-zig subnet-blob-msg
	@echo "Testing all-zig subnet-blob-msg"
	@uv run run.py --node_count 4 --composition zig --scenario "subnet-blob-msg" && uv run checks/subnet_blob_msg.py latest/

.PHONY: binaries all clean test test-rust-only test-go test-subnet-blob test-partial-messages test-zig
