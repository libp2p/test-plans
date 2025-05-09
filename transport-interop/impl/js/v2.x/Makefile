image_name := js-v2.x

# TODO Enable webkit once https://github.com/libp2p/js-libp2p/pull/1627 is in
all: image.json chromium-image.json firefox-image.json update-lock-file

# Necessary because multistage builds require a docker image name rather than a digest to be used
load-image-json: image.json
	docker image tag $$(jq -r .imageID image.json) node-${image_name}

image.json:
	docker builder prune -af
	docker build -t node-${image_name} -f ./Dockerfile .
	docker image inspect node-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

chromium-image.json: load-image-json
	docker build -f BrowserDockerfile --build-arg=BASE_IMAGE=node-${image_name} --build-arg=BROWSER=chromium -t chromium-${image_name} .
	docker image inspect chromium-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

firefox-image.json: load-image-json
	docker build -f BrowserDockerfile --build-arg=BASE_IMAGE=node-${image_name} --build-arg=BROWSER=firefox -t firefox-${image_name} .
	docker image inspect firefox-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# We update the lock file here so that we make sure we are always using the correct lock file.
# If this changes, CI will fail since there are unstaged changes.
update-lock-file: image.json
	CONTAINER_ID=$$(docker create $$(jq -r .imageID image.json)); \
	docker cp $$CONTAINER_ID:/app/package-lock.json ./package-lock.json; \
	docker rm $$CONTAINER_ID

clean:
	rm -rf *-image.json

.PHONY: clean
