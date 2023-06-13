image_name := go-v0.28
commitSha := 703c3a4377d1ca2cf3fc93c92c883be1644f3ba6

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

