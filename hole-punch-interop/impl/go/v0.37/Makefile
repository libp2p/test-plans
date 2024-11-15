image_name := go-v0.37

all: image.json

image.json: main.go Dockerfile go.mod go.sum
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: debug-image.json
# You may need to change GOARCH if your docker host isn't arm64
debug-image.json:
	GOARCH=arm64 GOOS=linux go build -o hole-punch-client .
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile.debug --tag holepunch-go-debug .

clean:
	rm image.json
