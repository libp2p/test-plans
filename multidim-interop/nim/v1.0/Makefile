imageName := nim-v1.0
commitSha := 408dcf12bdf44dcd6f9021a6c795c472679d6d02
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
image.json: main.nim nim-libp2p Dockerfile
	docker build -t ${imageName} .
	docker image inspect ${imageName} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@
	# If we're in CI, save the cache
	if [[ -n "$${CI:-}" ]]; then IMAGE_NAME=${imageName} CACHE_KEY=${cacheKey} ../../helpers/saveCache.sh; fi
endif


main.nim: ../mainv1.nim
	cp ../mainv1.nim main.nim

nim-libp2p: nim-libp2p-${commitSha}
	rm -rf nim-libp2p
	ln -s nim-libp2p-${commitSha} nim-libp2p

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

.PHONY: clean all

clean:
	rm -f main.nim
	rm -f image.json
	rm -rf nim-libp2p*
