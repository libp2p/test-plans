image_name := python-v0.4
commitSha := c0dedaae41a8a6da73a7a4d34484a452dd4b08f4

all: image.json

image.json: py-libp2p-${commitSha}.zip
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

py-libp2p-${commitSha}: py-libp2p-${commitSha}.zip
	unzip py-libp2p-${commitSha}.zip

py-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/py-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm py-libp2p-*.zip
	rm -rf py-libp2p-*

.PHONY: clean all
