image_name := zig-v0.0.1
commitSha := 7d8949158767de1145e9cdb2c6bf93588413da90

all: image.json print-cpu-info

print-cpu-info: image.json
	docker run --rm --entrypoint /app/zig/bin/zig $$(jq -r .imageID image.json) build-exe --show-builtin

image.json:
	wget -O zig-libp2p-${commitSha}.zip "https://github.com/marcopolo/zig-libp2p/archive/${commitSha}.zip"
	unzip -o zig-libp2p-${commitSha}.zip
	cd zig-libp2p-${commitSha} && docker build -t ${image_name} -f interop/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json zig-libp2p-*.zip zig-libp2p-*

.PHONY: all clean print-cpu-info
