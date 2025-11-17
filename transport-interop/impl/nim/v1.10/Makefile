image_name := nim-v1.10
commitSha := 3a7745f920d11fb29305070cd9991874529dfc28

all: image.json

image.json: nim-libp2p-${commitSha}
	cd nim-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f interop/transport/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm nim-libp2p-*.zip
	rm -rf nim-libp2p-*

.PHONY: clean all

