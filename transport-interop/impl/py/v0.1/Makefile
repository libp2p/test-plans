image_name := py-v0.1

all: image.json

image.json:
	cd src && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -f image.json

.PHONY: clean all