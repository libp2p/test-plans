image_name := eth-p2p-z-v0.0.1
commitSha := 7e16c6d1598726e8f5ea9385b2c1d5cc1027255e

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
