commitSha := 488f0072cb937394d6c5c4678a5504b63403316e

all: perf

perf: rust-libp2p-${commitSha}/target/release/perf
	cp ./rust-libp2p-${commitSha}/target/release/perf .

rust-libp2p-${commitSha}/target/release/perf: rust-libp2p-${commitSha}
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/rust-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp rust:1.69 cargo build --release --bin perf

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
# TODO: Change to libp2p
	wget -O $@ "https://github.com/mxinden/rust-libp2p/archive/${commitSha}.zip"

clean:
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*

.PHONY: all clean run
