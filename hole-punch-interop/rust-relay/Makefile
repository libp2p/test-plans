image_name := hole-punch-test-rust-relay

all: image.json

image.json: Cargo.lock src/** Dockerfile
	IMAGE_NAME=${image_name} ../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
clean:
	rm -f image.json
