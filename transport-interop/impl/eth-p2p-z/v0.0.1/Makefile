image_name := eth-p2p-z-v0.1.0
commitSha := 6af992bace67944c9e0219c8a55443fa13932d9d

all: image.json

image.json: eth-p2p-z-${commitSha}
	cd eth-p2p-z-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f interop/transport/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

eth-p2p-z-${commitSha}: eth-p2p-z-${commitSha}.zip
	unzip -o $<

eth-p2p-z-${commitSha}.zip:
	wget -O $@ "https://github.com/zen-eth/eth-p2p-z/archive/${commitSha}.zip"

clean:
	rm image.json
	rm -f eth-p2p-z-*.zip
	rm -rf eth-p2p-z-*

.PHONY: all clean
