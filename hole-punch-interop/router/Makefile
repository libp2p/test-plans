image_name := hole-punch-test-router

all: image.json

image.json: Dockerfile run.sh
	IMAGE_NAME=${image_name} ../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
clean:
	rm -f image.json
