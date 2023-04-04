SHELL := /usr/bin/env bash
imageName := rust-v0.49
commitSha := 582c84043050eb0dd6e52d1bd0527175181d41cb
cacheKey := ${commitSha}
shouldUseCache := ${shell IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/shouldUseCache.sh}

all: image.json

ifneq (${shouldUseCache},)
# We have a cached image, let's use it
image.json:
	echo "Using cached image ${shouldUseCache} f"
	CACHE_KEY=${cacheKey} IMAGE_NAME=${imageName} ../../helpers/tryLoadCache.sh
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
else
image.json: rust-libp2p-${commitSha}
	cd rust-libp2p-${commitSha} && docker buildx build --load -f interop-tests/Dockerfile -t ${imageName} .
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
	# If we're in CI, save the cache
	if [[ -n "$${CI:-}" ]]; then IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/saveCache.sh; fi
endif

rust-libp2p-${commitSha}: rust-libp2p-${commitSha}.zip
	unzip -o rust-libp2p-${commitSha}.zip

rust-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/rust-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm rust-libp2p-*.zip
	rm -rf rust-libp2p-*
