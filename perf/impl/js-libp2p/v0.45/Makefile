commitSha := 59dc3aace9e01f197d0d00d72d7a5b00267085b9

all: perf

perf: build-project
	cp -r ./js-libp2p-${commitSha}/packages/perf perf-tests

build-project: extract
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:18.17.0 npm install
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:18.17.0 npm run build

extract: js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

js-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"

clean:
	rm -rf js-libp2p-*.zip
	rm -rf js-libp2p-*

.PHONY: all clean
