image_name := nim-v2.0
commitSha := c43199378f46d0aaf61be1cad1ee1d63e8f665d6

all: image.json

image.json: nim-libp2p-${commitSha}
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile nim-libp2p-${commitSha}
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
