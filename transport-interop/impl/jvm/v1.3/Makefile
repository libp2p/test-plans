image_name := jvm-libp2p-v1.3
commitSha := d0668fd56338d3618ccb19eb4b7bfeede888c27d

all: image.json

image.json:
	wget -O jvm-libp2p-${commitSha}.zip "https://github.com/libp2p/jvm-libp2p/archive/${commitSha}.zip"
	unzip -o jvm-libp2p-${commitSha}.zip
	cd jvm-libp2p-${commitSha} && \
	    docker build -t ${image_name} -f Dockerfile . 
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json jvm-libp2p-*.zip jvm-libp2p-*
