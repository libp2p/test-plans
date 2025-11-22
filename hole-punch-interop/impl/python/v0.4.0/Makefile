image_name := python-v0.4.0

.PHONY: all build clean

all: image.json

image.json: Dockerfile
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

build: image.json

clean:
	rm -f image.json
	docker rmi ${image_name} || true