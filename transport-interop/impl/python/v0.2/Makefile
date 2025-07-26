image_name := python-v0.2.9-git

all: image.json

image.json: ping_test.py pyproject.toml
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Force rebuild without cache (always downloads fresh packages from git)
force-rebuild: ping_test.py pyproject.toml
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh --no-cache -f PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Help target
help:
	@echo "Available targets:"
	@echo "  all          - build Docker image using cached layers (fast)"
	@echo "  force-rebuild - build Docker image without cache (always fresh git packages)"
	@echo "  clean        - remove generated image.json file"
	@echo "  help         - show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make all          # build with cache (recommended for development)"
	@echo "  make force-rebuild # build without cache (ensures latest git packages)"
	@echo "  make clean        # remove build artifacts"

.PHONY: clean all force-rebuild help

clean:
	rm -f image.json 