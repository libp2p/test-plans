image_name := nim-v1.14.x
commitSha := 0309685cd27d4bf763c8b3be86a76c33bcfe67ea

all: image.json

image.json: main.nim nim-libp2p Dockerfile
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

main.nim: ../mainv1.nim
	cp ../mainv1.nim main.nim

nim-libp2p: nim-libp2p-${commitSha}
	rm -rf nim-libp2p
	ln -s nim-libp2p-${commitSha} nim-libp2p

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

.PHONY: clean all

clean:
	rm -f main.nim
	rm -f image.json
	rm -rf nim-libp2p*
