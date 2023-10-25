commitSha := 26b3c9d43e65f379a6f384017eb8902133bbf8c2

all: perf

perf: rust-libp2p-${commitSha}/target/release/perf
	cp ./rust-libp2p-${commitSha}/target/release/perf .

rust-libp2p-${commitSha}/target/release/perf: rust-libp2p-${commitSha}
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/rust-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp rust:1.73 cargo build --release --bin perf

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
	# TODO: revert
	wget -O $@ "https://github.com/mxinden/rust-libp2p/archive/${commitSha}.zip"

clean:
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*
	rm perf

.PHONY: all clean
