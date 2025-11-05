image_name := go-v0.38
version := 0.38.1

all: image.json

image.json: verify-checksum go-libp2p-${version}
	cd go-libp2p-${version} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f test-plans/PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

go-libp2p-${version}: go-libp2p-${version}.zip
	unzip -o go-libp2p-${version}.zip

go-libp2p-${version}.zip:
	wget -O $@ "https://github.com/libp2p/go-libp2p/archive/v${version}.zip"

# Run `make version.lock` to generate this lock file. This file should be commited.
# This locks the exact contents of the specified version. This lets us use the
# human readable name while still making sure the contents don't change.
version.lock: go-libp2p-${version}.zip
	shasum -a 256 go-libp2p-${version}.zip > $@

verify-checksum: go-libp2p-${version}.zip
	shasum -a 256 -c version.lock

.PHONY: clean all verify-checksum

clean:
	rm image.json
	rm go-libp2p-*.zip
	rm -rf go-libp2p-*
