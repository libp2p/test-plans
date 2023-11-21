image_name := nim-v1.1
commitSha := ce0685c272e41614e97583f0a8dec2b6506913fd

all: image.json

image.json: hole_punching.nim nim-libp2p Dockerfile
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

hole_punching.nim: ../hole_punching.nim
	cp ../hole_punching.nim hole_punching.nim

nim-libp2p: nim-libp2p-${commitSha}
	rm -rf nim-libp2p
	ln -s nim-libp2p-${commitSha} nim-libp2p

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm -f nim-libp2p
	rm -rf nim-libp2p-*

.PHONY: all clean
