all: v0.49/image.json v0.50/image.json

v0.49/image.json: Dockerfile src/*/*.rs src/*.rs Cargo.lock Cargo.toml
	mkdir -p $(shell dirname $@)
	echo "{\"imageID\": \"$(shell docker build . -q  --build-arg BINARY_NAME=testplan_0490)\"}" > $@

v0.50/image.json: Dockerfile src/*/*.rs src/*.rs Cargo.lock Cargo.toml
	mkdir -p $(shell dirname $@)
	echo "{\"imageID\": \"$(shell docker build . -q  --build-arg BINARY_NAME=testplan_0500)\"}" > $@

clean:
	rm v0.49/image.json
	rm v0.50/image.json
