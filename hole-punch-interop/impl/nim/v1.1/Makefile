image_name := nim-v1.1
commitSha := 93925ac28b04cd94d06a332412973e90f80f35df

all: image.json

image.json: nim-libp2p-${commitSha}
	cd nim-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f tests/hole-punching-interop/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm -f image.json
	rm -rf nim-libp2p*

.PHONY: all clean
