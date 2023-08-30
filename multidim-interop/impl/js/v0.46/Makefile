NPM_PACKAGE_VERSION := 1.0.0
NPM_PACKAGE := @libp2p/multidim-interop
NPM_PACKAGE_NAME := $(NPM_PACKAGE)@$(NPM_PACKAGE_VERSION)

SOURCE_DIR := js-libp2p-multidim

DOCKER_IMAGE := node:18.17.1

DOCKER_RUN := docker run --rm -v "$(shell pwd)/$(SOURCE_DIR)":/usr/src/myapp -w /usr/src/myapp $(DOCKER_IMAGE)

image_name := js-v0.46

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

image.json:
	mkdir -p $(SOURCE_DIR)
	$(DOCKER_RUN) npm install $(NPM_PACKAGE_NAME)
	cd js-libp2p-multidim && docker build -t ${image_name} -f ../Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@


clean:
	rm -rf image.json js-libp2p-*.zip js-libp2p-* *-image.json

.PHONY: all clean browser-images load-image-json
