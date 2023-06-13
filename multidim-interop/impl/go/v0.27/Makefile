image_name := go-v0.27
commitSha := 2df518f43fa2c3e937b81c249c2c5b898421df6b

all: image.json

image.json: go-libp2p-${commitSha}
	cd go-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f test-plans/PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

go-libp2p-${commitSha}: go-libp2p-${commitSha}.zip
	unzip -o go-libp2p-${commitSha}.zip

go-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/go-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm go-libp2p-*.zip
	rm -rf go-libp2p-*
