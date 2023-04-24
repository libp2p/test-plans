image_name := rust-v0.51
commitSha := 66a28b37d8deb4d0e38e61f5d3ca0d34368f5770

all: image.json

image.json: rust-libp2p-${commitSha}
# TODO: Consider removing sudo
	cd rust-libp2p-${commitSha} && docker build -t ${image_name} -f protocols/perf/Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
# TODO: Change to libp2p
	wget -O $@ "https://github.com/mxinden/rust-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*

.PHONY: all clean
