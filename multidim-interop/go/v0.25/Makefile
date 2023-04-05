SHELL := /usr/bin/env bash
imageName := go-v0.25
commitSha := 5741b6c9bbcc1185bdf94d816dca966b37ce61ff
cacheKey := ${commitSha}
shouldUseCache := ${shell IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/shouldUseCache.sh}

all: image.json

ifneq (${shouldUseCache},)
# We have a cached image, let's use it
image.json:
	CACHE_KEY=${cacheKey} IMAGE_NAME=${imageName} ../../helpers/tryLoadCache.sh
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
else
image.json: go-libp2p-${commitSha}
	cd go-libp2p-${commitSha} && docker build -t ${imageName} -f test-plans/PingDockerfile .
	# If we're in CI, save the cache
	IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/maybePushCache.sh
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
endif

go-libp2p-${commitSha}: go-libp2p-${commitSha}.zip
	unzip -o go-libp2p-${commitSha}.zip

go-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/go-libp2p/archive/${commitSha}.zip"

clean:
	rm image.json
	rm go-libp2p-*.zip
	rm -rf go-libp2p-*
