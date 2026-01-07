# Default target
all: binaries

binaries:
	cd go-libp2p && go build -o gossipsub-bin
	# Skip rust for now - requires local rust-libp2p checkout
	# cd rust-libp2p && cargo build
	# Build JVM binary
	cd jvm-libp2p && ./gradlew shadowJar --no-daemon -q

# Clean all generated shadow simulation files
clean:
	rm -rf shadow-outputs || true
	rm plots/* || true

test:
	# Testing partial messages
	@echo "Testing partial messages"
	@uv run run.py --node_count 32 --composition "rust-and-go" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing partial messages chain"
	@uv run run.py --node_count 8 --composition "rust-and-go" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

	@echo "Testing fanout"
	@uv run run.py --node_count 8 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	@uv run run.py --node_count 8 --seed 1 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	@uv run run.py --node_count 8 --seed 2 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	@uv run run.py --node_count 8 --seed 3 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

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



test-jvm:
	# Testing JVM partial messages
	@echo "Testing JVM partial messages"
	@uv run run.py --node_count 2 --composition "all-jvm" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

	@echo "Testing JVM partial messages chain"
	@uv run run.py --node_count 8 --composition "all-jvm" --scenario "partial-messages-chain" && uv run checks/partial_messages.py latest --count 16

test-jvm-and-go:
	# Testing JVM and Go interop
	@echo "Testing JVM and Go partial messages"
	@uv run run.py --node_count 4 --composition "jvm-and-go" --scenario "partial-messages" && uv run checks/partial_messages.py latest --count 1

.PHONY: binaries all clean test test-jvm test-jvm-and-go
