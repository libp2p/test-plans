image_name := python-v0.4

all: image.json

image.json: ping_test.py pyproject.toml
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Force rebuild without cache (always downloads fresh packages from git)
force-rebuild: ping_test.py pyproject.toml
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh --no-cache -f Dockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > image.json

clean:
	rm -f image.json
	rm -f force-rebuild
	docker rmi ${image_name} 2>/dev/null || true

.PHONY: clean all force-rebuild
