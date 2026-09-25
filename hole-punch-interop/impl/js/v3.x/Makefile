image_name := js-v3.x

all: image.json

image.json: src/index.ts Dockerfile package.json package-lock.json tsconfig.json
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -f image.json
