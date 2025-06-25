image_name := c-v0.0.1
commitSha := f20d98be040c7600d8f559ab4d62559326a2439a
zip_name := c-libp2p-$(commitSha).zip
dir_name := c-libp2p-$(commitSha)

all: image.json

image.json:
	wget -O $(zip_name) https://github.com/Pier-Two/c-libp2p/archive/$(commitSha).zip && unzip -o $(zip_name)
	cd $(dir_name) && IMAGE_NAME=$(image_name) ../../../../dockerBuildWrapper.sh --platform linux/amd64 -f interop-tests/Dockerfile .
	docker image inspect $(image_name) -f '{{.Id}}' | \
		xargs -I {} echo '{"imageID": "{}"}' > $@

clean:
	rm -rf image.json $(dir_name) $(zip_name)

.PHONY: all clean
