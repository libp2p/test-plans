image_name := python-v0.x
commitSha := f6ade8457d56e8807b0bdfa25feb858c6473aea1

# Default: vendor py-libp2p from GitHub at commitSha (see py-libp2p-${commitSha}.zip).
# To use a local checkout (e.g. with relay fixes not yet in that commit):
#   make image.json PY_LIBP2P_DIR=/absolute/path/to/py-libp2p
# Example (Libp2p layout: sibling test-plans and py-libp2p), from this directory:
#   make image.json PY_LIBP2P_DIR=$(cd ../../../../../py-libp2p && pwd)

all: image.json

image.json: py-libp2p-${commitSha} Dockerfile hole_punch_client.py pyproject.toml hole-punch-client
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# With PY_LIBP2P_DIR: rsync local tree into py-libp2p-<commit>/ (no zip). Otherwise: unzip GitHub archive.
py-libp2p-${commitSha}: $(if $(PY_LIBP2P_DIR),,py-libp2p-${commitSha}.zip)
	@if [ -n "$(PY_LIBP2P_DIR)" ]; then \
		rm -rf $@ && mkdir -p $@ && \
		rsync -a --delete "$(PY_LIBP2P_DIR)"/ $@/; \
	else \
		unzip -o py-libp2p-${commitSha}.zip; \
	fi

py-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/py-libp2p/archive/${commitSha}.zip"

clean:
	rm -f image.json
	rm -f py-libp2p-*.zip
	rm -rf py-libp2p-*

.PHONY: clean all
