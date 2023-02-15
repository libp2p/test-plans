image_name := nim-v1.0

image.json: Dockerfile main.nim
	IMAGE_NAME=${image_name} ../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm image.json
