image_name := rust-v0.54
commitSha := d7beb55f672dce54017fa4b30f67ecb8d66b9810

all: image.json

image.json: rust-libp2p-${commitSha}
	cd rust-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f hole-punching-tests/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/rust-libp2p/archive/${commitSha}.zip"

debug-image.json:
	cd rust-libp2p-${commitSha}/hole-punching-tests && cargo build --target aarch64-unknown-linux-musl
	cp rust-libp2p-${commitSha}/target/aarch64-unknown-linux-musl/debug/hole-punching-tests hole-punch-client
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile.debug --tag holepunch-rust-debug .
	rm hole-punch-client

clean:
	rm image.json
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*
