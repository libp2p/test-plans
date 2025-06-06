image_name := c-v0.0.1
commitSha := 8b5a07037f173ff749ba4520652acfbbdf625846
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
