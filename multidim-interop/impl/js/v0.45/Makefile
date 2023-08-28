image_name := js-v0.45
commitSha := 47a96706527fd82cd9daf3cc298f56866a5d027a

# TODO Enable webkit once https://github.com/libp2p/js-libp2p/pull/1627 is in
all: image.json chromium-image.json firefox-image.json

# Necessary because multistage builds require a docker image name rather than a digest to be used
load-image-json: image.json
	docker image tag $$(jq -r .imageID image.json) ${image_name}

chromium-image.json: load-image-json BrowserDockerfile
	docker build -f BrowserDockerfile --build-arg=BASE_IMAGE=${image_name} --build-arg=BROWSER=chromium -t chromium-${image_name} .
	docker image inspect chromium-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

firefox-image.json: load-image-json BrowserDockerfile
	docker build -f BrowserDockerfile --build-arg=BASE_IMAGE=${image_name} --build-arg=BROWSER=firefox -t firefox-${image_name} .
	docker image inspect firefox-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

image.json: js-libp2p-${commitSha}
	cd js-libp2p-${commitSha} && docker build -t ${image_name} -f ../Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

js-libp2p-${commitSha}:
	wget --secure-protocol TLSv1_2 -O js-libp2p-${commitSha}.zip "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"
	unzip -o js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

clean:
	rm -rf image.json js-libp2p-*.zip js-libp2p-* *-image.json

.PHONY: all clean browser-images load-image-json
