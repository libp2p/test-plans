# Default target
all: binaries

binaries:
	cd go-libp2p && go build -linkshared -o gossipsub-bin
	cd rust-libp2p && cargo build

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
	uv run run.py --node_count 8 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 1 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 2 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/
	uv run run.py --node_count 8 --seed 3 --composition "rust-and-go" --scenario "partial-messages-fanout" && uv run checks/partial_messages.py latest/

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


blocks-data-columns-race: binaries
	@uv run run.py --node_count 128 --composition "all-go" --scenario "two-topics"
	@echo "Block received timings"
	@rg --no-filename "Received Mess.*blocks" latest/hosts/node*/*.stdout -m 1 | jq -r '.time' | python3 ./checks/stats_ts.py --relative-to "2000-01-01T00:00:30Z"
	@echo "Data Column received timings"
	@rg --no-filename "Received Mess.*data_columns" latest/hosts/node*/*.stdout -m 1 | jq -r '.time' | python3 ./checks/stats_ts.py --relative-to "2000-01-01T00:00:30.00000000Z"

eager-vs-lazy-publisher:
	@uv run run.py --node_count 1024 --seed 3 --composition "all-go" --scenario "partial-messages-lazy"
	@uv run run.py --node_count 1024 --seed 3 --composition "all-go" --scenario "partial-messages-eager"


.PHONY: binaries all clean test blocks-data-columns-race
