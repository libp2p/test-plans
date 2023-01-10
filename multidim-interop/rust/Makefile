all: v0.50/image.json

v0.50/image.json: Dockerfile src/*/*.rs src/*.rs Cargo.lock Cargo.toml
	mkdir -p $(shell dirname $@)
	IMAGE_NAME=rust-$@ ../dockerBuildWrapper.sh . --build-arg BINARY_NAME=testplan_0500
	docker image inspect rust-$@ -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm v0.50/image.json

.PHONY: clean all