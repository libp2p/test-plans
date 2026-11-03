image_name := rust-v0.56

all: image.json

image.json: Cargo.toml Cargo.lock src/** Dockerfile
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm image.json
