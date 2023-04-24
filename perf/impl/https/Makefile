image_name := https

all: image.json

image.json:
# TODO: Consider removing sudo
	docker build -t ${image_name} .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

clean:
	rm image.json
