imageName := js-v0.41
TEST_SOURCES := $(wildcard test/*.ts)

all: node-${imageName}-image.json chromium-${imageName}-image.json


node-${imageName}-image.json: Dockerfile $(TEST_SOURCES) package.json package-lock.json .aegir.js build.ts
	PATH=$$PATH:../../node_modules/.bin ts-node-esm --skipProject -O '{"module":"es2022"}' ./build.ts node-${imageName}

chromium-${imageName}-image.json: ChromiumDockerfile $(TEST_SOURCES) node-${imageName}-image.json
	docker build -t chromium-${imageName} -f ChromiumDockerfile --build-arg="BASE_IMAGE=node-${imageName}" .
	docker image inspect chromium-${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm *image.json
