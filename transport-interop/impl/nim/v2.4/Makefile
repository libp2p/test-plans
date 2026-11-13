image_name := nim-v2.4
commitSha := 8768d4dadcd55de1c23a0056a9b3facdd55c9bbb

all: image.json

image.json: nim-libp2p-${commitSha}
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f nim-libp2p-${commitSha}/interop/transport/Dockerfile nim-libp2p-${commitSha}
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/iftech/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm -f image.json
	rm -f nim-libp2p-*.zip
	rm -rf nim-libp2p-*

.PHONY: clean all
