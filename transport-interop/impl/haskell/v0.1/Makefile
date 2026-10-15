image_name := haskell-v0.1
commitSha := 574acdc43f824090f8d397e4e36ea8a5d2fb8317

all: image.json

# Build the image from libp2p-hs's own root Dockerfile, which compiles the
# libp2p-interop daemon. dockerBuildWrapper.sh runs:
#   docker buildx build --load -t $(image_name) .
image.json: libp2p-hs-${commitSha}
	cd libp2p-hs-${commitSha} && IMAGE_NAME=${image_name} ../../../../dockerBuildWrapper.sh .
	docker image inspect ${image_name} -f "{{.Id}}" | \
		xargs -I {} echo "{\"imageID\": \"{}\"}" > $@

libp2p-hs-${commitSha}: libp2p-hs-${commitSha}.zip
	unzip -o libp2p-hs-${commitSha}.zip

libp2p-hs-${commitSha}.zip:
	wget -O $@ "https://github.com/adust09/libp2p-hs/archive/${commitSha}.zip"

.PHONY: clean all

clean:
	rm -f image.json
	rm -f libp2p-hs-*.zip
	rm -rf libp2p-hs-*
