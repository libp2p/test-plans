image_name := nim-v1.14
commitSha := 0309685cd27d4bf763c8b3be86a76c33bcfe67ea

all: image.json

image.json: nim-libp2p-${commitSha}
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm main.nim
	rm image.json
	rm nim-libp2p-*.zip
	rm -rf nim-libp2p-*

.PHONY: clean all
