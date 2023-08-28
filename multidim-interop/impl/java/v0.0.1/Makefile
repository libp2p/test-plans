image_name := java-v0.0.1
commitSha := 6fad470c92a5c4ab368bc615e64dbf40b5ff9ccb

all: image.json

image.json:
	wget --secure-protocol TLSv1.3 -O java-libp2p-${commitSha}.zip "https://github.com/Peergos/nabu/archive/${commitSha}.zip"
	unzip -o java-libp2p-${commitSha}.zip
	cd nabu-${commitSha} && docker build -t ${image_name} -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json java-libp2p-*.zip nabu-*
