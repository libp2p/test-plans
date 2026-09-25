image_name := hole-punch-test-go-relay

all: image.json

image.json: main.go go.mod go.sum Dockerfile
	IMAGE_NAME=${image_name} ../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
clean:
	rm image.json
