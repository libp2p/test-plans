image_name := js-v0.21

image.json: Dockerfile index.js package.json package-lock.json
	IMAGE_NAME=${image_name} ../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm image.json