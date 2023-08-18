image_name := kotlin-v0.2
version := 0.2.0

all: image.json

image.json: verify-checksum kotlin-libp2p-${version}
	cd kotlin-libp2p-${version} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f test-plans/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

kotlin-libp2p-${version}: kotlin-libp2p-${version}.zip
	unzip -o kotlin-libp2p-${version}.zip

kotlin-libp2p-${version}.zip:
	wget -O $@ "https://github.com/erwin-kok/kotlin-libp2p/archive/v${version}.zip"

# Run `make version.lock` to generate this lock file. This file should be committed.
# This locks the exact contents of the specified version. This lets us use the
# human readable name while still making sure the contents don't change.
version.lock: kotlin-libp2p-${version}.zip
	shasum -a 256 kotlin-libp2p-${version}.zip > $@

verify-checksum: kotlin-libp2p-${version}.zip
	shasum -a 256 -c version.lock

.PHONY: clean all verify-checksum

clean:
	-rm image.json
	-rm kotlin-libp2p-*.zip
	-rm -rf kotlin-libp2p-*
