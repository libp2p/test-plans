image_name := python-v0.4
commitSha := 09d0064f1d1dbee64a148d72374ed51ecc80ad4d

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
