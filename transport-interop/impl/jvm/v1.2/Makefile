image_name := jvm-libp2p-v1.2
commitSha := 737456de5d96db030aa04c8527585af1a510898f

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
