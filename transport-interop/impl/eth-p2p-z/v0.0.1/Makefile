image_name := eth-p2p-z-v0.0.1
commitSha := a517a15d7845698c56c37e9135d45eb437660845
ZIG_LOG_LEVEL ?= warn

all: image.json

image.json: eth-p2p-z-${commitSha}
	cd eth-p2p-z-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f interop/transport/Dockerfile --build-arg ZIG_LOG_LEVEL=$(ZIG_LOG_LEVEL) .
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
