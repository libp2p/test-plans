image_name := c-v0.0.1
commitSha := f7c2f9386cd45489d768f7e0424a3022d0d21d69
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
