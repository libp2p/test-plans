image_name := rust-v0.50
commitSha := 1f0f0e240cc25480d1b5fb488abfb69bf06812f0

all: image.json

image.json: rust-libp2p-${commitSha}
	cd rust-libp2p-${commitSha} && IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f interop-tests/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/rust-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*