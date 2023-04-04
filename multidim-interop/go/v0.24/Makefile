SHELL := /usr/bin/env bash
imageName := go-v0.24

cacheKey=${shell git ls-files  | tr "\n" " " | xargs ../../helpers/hashFiles.sh}
shouldUseCache := ${shell IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/shouldUseCache.sh}

all: image.json

ifneq (${shouldUseCache},)
# We have a cached image, let's use it
image.json:
	CACHE_KEY=${cacheKey} IMAGE_NAME=${imageName} ../../helpers/tryLoadCache.sh
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
else
image.json: Dockerfile main.go go.mod go.sum
	docker build -t ${imageName} .
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
	# If we're in CI, save the cache
	if [[ -n "$${CI:-}" ]]; then IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/saveCache.sh; fi
endif

.PHONY: clean

clean:
	rm image.json
