image_name := c-v0.0.1
commitSha := 8374eaadca988020bfbdfbaba72094f7ef1705b1
# directory name based on commit
 dir_name := c-libp2p-$(commitSha)

all: image.json

image.json:
	# Clean previous source
	rm -rf $(dir_name)
	# Download source zip for the specific commit
	wget -O $(dir_name).zip https://github.com/Pier-Two/c-libp2p/archive/$(commitSha).zip
	# Verify checksum against version.lock
	shasum -a 256 -c version.lock
	# Unpack source
	unzip -o $(dir_name).zip
	# Build Docker image using the specified Dockerfile
	cd $(dir_name) && docker build -t $(image_name) -f ../../../../../../test-plans/transport-interop/impl/c/v0.0.1/Dockerfile .
	# Record image ID
	docker image inspect $(image_name) -f '{{.Id}}' | \
		xargs -I {} echo '{"imageID": "{}"}' > image.json

clean:
	rm -rf image.json $(dir_name) $(dir_name).zip

.PHONY: all clean