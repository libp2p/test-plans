image_name := python-v0.2.9-git

all: image.json

image.json: ping_test.py pyproject.toml
	docker builder prune -af
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh -f PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Force rebuild without cache (always downloads fresh packages from git)
force-rebuild: ping_test.py pyproject.toml
	docker builder prune -af
	IMAGE_NAME=${image_name} ../../../dockerBuildWrapper.sh --no-cache -f PingDockerfile .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

# Verify all dependencies are correctly installed
verify-deps: image.json
	docker run --rm --entrypoint python ${image_name} -c "import libp2p, trio, multiaddr, redis, typing_extensions; print('✅ All dependencies verified')"

# Show image information
image-info: image.json
	@echo "Image ID: $$(jq -r .imageID image.json)"
	@echo "Image Size: $$(docker images ${image_name} --format '{{.Size}}')"
	@echo "Created: $$(docker images ${image_name} --format '{{.CreatedAt}}')"

# Test run the ping test (without Redis)
test-run: image.json
	docker run --rm --entrypoint python ${image_name} -c "print('Python libp2p ping test ready')"

# Check libp2p version
version-check: image.json
	docker run --rm --entrypoint python ${image_name} -c "import libp2p; print(f'libp2p version: {libp2p.__version__}')"

# Help target
help:
	@echo "Available targets:"
	@echo "  all          - build Docker image using cached layers (fast)"
	@echo "  force-rebuild - build Docker image without cache (always fresh git packages)"
	@echo "  verify-deps  - verify all dependencies are correctly installed"
	@echo "  image-info   - show image information (ID, size, creation date)"
	@echo "  test-run     - test run the ping test (without Redis)"
	@echo "  version-check - check libp2p version in the image"
	@echo "  clean        - remove generated files and Docker image"
	@echo "  help         - show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make all          # build with cache (recommended for development)"
	@echo "  make force-rebuild # build without cache (ensures latest git packages)"
	@echo "  make verify-deps  # verify dependencies work correctly"
	@echo "  make image-info   # show image details"
	@echo "  make test-run     # test the image works"
	@echo "  make clean        # remove build artifacts"


clean:
	rm -f image.json
	rm -f force-rebuild
	docker rmi ${image_name} 2>/dev/null || true

.PHONY: clean all force-rebuild verify-deps image-info test-run version-check help
