image_name := java-v0.6
commitSha := f917cc40060fcffc0b7ee9c66a04b35fb1b0a9bd

all: image.json

image.json:
	wget -O java-libp2p-${commitSha}.zip "https://github.com/Peergos/nabu/archive/${commitSha}.zip"
	unzip -o java-libp2p-${commitSha}.zip
	cd nabu-${commitSha} && docker build -t ${image_name} -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json java-libp2p-*.zip nabu-*
