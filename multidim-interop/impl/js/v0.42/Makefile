image_name := js-v0.42
TEST_SOURCES := $(wildcard test/*.ts)

all: chromium-image.json node-image.json

chromium-image.json: ChromiumDockerfile $(TEST_SOURCES) package.json package-lock.json .aegir.js
	IMAGE_NAME=chromium-${image_name} ../../../dockerBuildWrapper.sh -f ChromiumDockerfile .
	docker image inspect chromium-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

node-image.json: Dockerfile $(TEST_SOURCES) package.json package-lock.json .aegir.js
	IMAGE_NAME=node-${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect node-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm *image.json
