image_name := rust-v0.51
version := 0.51.3

all: image.json

image.json: verify-checksum rust-libp2p-${version}
	cd rust-libp2p-${version} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f interop-tests/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

rust-libp2p-${version}: rust-libp2p-${version}.zip
	unzip -o rust-libp2p-${version}.zip

rust-libp2p-${version}.zip:
	wget -O $@ "https://github.com/libp2p/rust-libp2p/archive/libp2p-v${version}.zip"

# Run `make version.lock` to generate this lock file. This file should be commited.
# This locks the exact contents of the specified version. This lets us use the
# human readable name while still making sure the contents don't change.
version.lock: rust-libp2p-${version}.zip
	shasum -a 256 rust-libp2p-${version}.zip > $@

verify-checksum: rust-libp2p-${version}.zip
	shasum -a 256 -c version.lock

.PHONY: clean all verify-checksum

clean:
	rm image.json
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*

