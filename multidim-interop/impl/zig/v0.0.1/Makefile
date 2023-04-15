image_name := zig-v0.0.1
commitSha := 7435381b698bf282d088a64de1b24f5767bb9a4a

all: image.json

image.json:
	wget -O zig-libp2p-${commitSha}.zip "https://github.com/marcopolo/zig-libp2p/archive/${commitSha}.zip"
	unzip -o zig-libp2p-${commitSha}.zip
	cd zig-libp2p-${commitSha} && docker build -t ${image_name} -f interop/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm -rf image.json zig-libp2p-*.zip zig-libp2p-*
