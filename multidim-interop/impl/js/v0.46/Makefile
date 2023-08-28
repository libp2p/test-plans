image_name := js-v0.46
commitSha := b7e608998cc88860d9ec8a3ed7c03fdfb3eccb3b

# TODO Enable webkit once https://github.com/libp2p/js-libp2p/pull/1627 is in
# We update the lock file here so that we make sure we are always using the correct lock file.
# If this changes, CI will fail since there are unstaged changes.
all: image.json chromium-image.json firefox-image.json update-lock-file

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

image.json: js-libp2p-${commitSha} js-libp2p-${commitSha}/package-lock.json
	cd js-libp2p-${commitSha} && docker build -t ${image_name} -f ../Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Include the package-lock.json file so this build is reproducible
js-libp2p-${commitSha}/package-lock.json: js-libp2p-${commitSha}
	cp ./package-lock.json js-libp2p-${commitSha}/package-lock.json

js-libp2p-${commitSha}:
	wget --secure-protocol TLSv1.3 -O js-libp2p-${commitSha}.zip "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"
	unzip -o js-libp2p-${commitSha}.zip

update-lock-file: image.json
	CONTAINER_ID=$$(docker create $$(jq -r .imageID image.json)); \
	docker cp $$CONTAINER_ID:/app/package-lock.json ./package-lock.json; \
	docker rm $$CONTAINER_ID

clean:
	-rm -rf image.json js-libp2p-*.zip js-libp2p-* *-image.json

.PHONY: all clean browser-images load-image-json update-lock-file
