image_name := minip2p-v0.11
commitSha := 2877abdaf7595c8b492b78850ed15506016099b5

all: image.json

image.json: minip2p-${commitSha}
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f minip2p-${commitSha}/tests/interop/unified-testing/Dockerfile minip2p-${commitSha}
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

minip2p-${commitSha}: minip2p-${commitSha}.zip
	unzip -o minip2p-${commitSha}.zip

minip2p-${commitSha}.zip:
	wget -O $@ "https://github.com/deepso7/minip2p/archive/${commitSha}.zip"

clean:
	rm -f image.json
	rm -f minip2p-*.zip
	rm -rf minip2p-*

.PHONY: clean all
