image_name := java-v0.0.1
commitSha := 70f88661f525078d92aebeb73d38875ac11b3193

all: image.json

image.json:
	wget -O java-libp2p-${commitSha}.zip "https://github.com/Peergos/nabu/archive/${commitSha}.zip"
	unzip -o java-libp2p-${commitSha}.zip
	cd nabu-${commitSha} && docker build -t ${image_name} -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json java-libp2p-*.zip nabu-*
