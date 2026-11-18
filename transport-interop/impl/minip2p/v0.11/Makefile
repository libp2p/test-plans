image_name := minip2p-v0.11
commitSha := 960193187315bd3af628fa8d243355941ce6d6d7

all: image.json

image.json: minip2p-${commitSha}
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f minip2p-${commitSha}/tests/interop/unified-testing/Dockerfile minip2p-${commitSha}
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

minip2p-${commitSha}: minip2p-${commitSha}.zip
	unzip -o minip2p-${commitSha}.zip

minip2p-${commitSha}.zip:
	wget -O $@ "https://github.com/yashksaini-coder/minip2p/archive/${commitSha}.zip"

clean:
	rm -f image.json
	rm -f minip2p-*.zip
	rm -rf minip2p-*

.PHONY: clean all
