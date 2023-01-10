image_name := go-v0.24

image.json: Dockerfile main.go go.mod go.sum
	IMAGE_NAME=${image_name} ../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

.PHONY: clean

clean:
	rm image.json