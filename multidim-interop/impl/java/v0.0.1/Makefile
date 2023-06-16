image_name := java-v0.0.1
commitSha := 89f724c4ca07eb4fc704176f91ad1f390b388cdb

all: image.json

image.json:
	wget -O java-libp2p-${commitSha}.zip "https://github.com/Peergos/nabu/archive/${commitSha}.zip"
	unzip -o java-libp2p-${commitSha}.zip
	cd nabu-${commitSha} && docker build -t ${image_name} -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json java-libp2p-*.zip nabu-*
