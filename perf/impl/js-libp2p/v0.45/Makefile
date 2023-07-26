image_name := js-v0.45
commitSha := b1d89bda6c7952b7d60f560894aadc1544cc53ce

all: perf

# Necessary because multistage builds require a docker image name rather than a digest to be used
perf: js-libp2p-${commitSha}/perf
	cp ./js-libp2p-${commitSha}/perf .

load-image-json: image.json
	docker image tag $$(jq -r .imageID image.json) ${image_name}

image.json: js-libp2p-${commitSha}
	cd js-libp2p-${commitSha} && docker build -t ${image_name} -f ../Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

js-libp2p-${commitSha}:
	wget -O js-libp2p-${commitSha}.zip "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"
	unzip -o js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

clean:
	rm -rf image.json js-libp2p-*.zip js-libp2p-* *-image.json

.PHONY: all clean
