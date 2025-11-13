image_name := python-v0.4
commitSha := e2c37df531cc4f5fdcf1b68ac642edb420531cc3

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
