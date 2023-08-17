image_name := kotlin-v0.1.0
commitSha := 10eb5f4109a3fa789b38553079aa0736dfa58201

all: image.json

image.json: kotlin-libp2p-${commitSha}
	cd kotlin-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f test-plans/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

kotlin-libp2p-${commitSha}:
	wget -O kotlin-libp2p-${commitSha}.zip "https://github.com/erwin-kok/kotlin-libp2p/archive/${commitSha}.zip"
	unzip -o kotlin-libp2p-${commitSha}.zip

.PHONY: clean all

clean:
	rm image.json
	rm kotlin-libp2p-*.zip
	rm -rf kotlin-libp2p-*
