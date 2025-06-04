image_name := c-v0.0.1
commitSha := 412167cd62b141c2bc48374cb5b39eb8d6042402
# directory name based on commit
 dir_name := c-libp2p-$(commitSha)

all: image.json

image.json:
	# Clean previous source
	rm -rf $(dir_name)
	# Clone repo with submodules for the specific commit
	git clone https://github.com/Pier-Two/c-libp2p.git $(dir_name)
	cd $(dir_name) && git checkout $(commitSha) && git submodule update --init --recursive
	# Generate Dockerfile from interop-tests, stripping stray 'en', fixing base image tag, and removing strip
	@echo "Generating Dockerfile from interop-tests, applying patches"
	@sed -e '/^en$$/d' \
	     -e 's|FROM ubuntu:22.04-slim|FROM ubuntu:22.04|' \
	     -e 's| && strip interop-c||' \
	     $(dir_name)/interop-tests/Dockerfile > $(dir_name)/Dockerfile
	# Build Docker image using the generated Dockerfile
	cd $(dir_name) && docker build -t $(image_name) -f Dockerfile .
	# Record image ID
	docker image inspect $(image_name) -f '{{.Id}}' | \
		xargs -I {} echo '{"imageID": "{}"}' > image.json

clean:
	rm -rf image.json $(dir_name)

.PHONY: all clean