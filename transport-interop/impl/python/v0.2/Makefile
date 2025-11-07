all: image.json

# image.json already exists from previous build
image.json:
	@test -f image.json || (echo "Error: image.json not found" && exit 1)

.PHONY: all

