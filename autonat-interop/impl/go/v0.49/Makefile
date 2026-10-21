image_name := go-v0.49

all: image.json

image.json: main.go Dockerfile go.mod go.sum
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm image.json
