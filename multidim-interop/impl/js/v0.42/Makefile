image_name := js-v0.42
TEST_SOURCES := $(wildcard test/*.ts)

all: chromium-image.json node-image.json

chromium-image.json: node-image.json
	docker build -t chromium-${image_name} -f ChromiumDockerfile --build-arg="BASE_IMAGE=node-${image_name}" .
	docker image inspect chromium-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

node-image.json: image.json
	docker image tag $$(cat image.json | jq -r '.imageID') node-${image_name}
	cp image.json node-image.json

image.json: Dockerfile $(TEST_SOURCES) package.json package-lock.json .aegir.js
	IMAGE_NAME=node-${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect node-${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm *image.json
