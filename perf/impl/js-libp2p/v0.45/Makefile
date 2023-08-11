commitSha := 3345f28b3b13fbe6b4e333466488e9d0bc677322

all: perf

perf: js-libp2p-${commitSha}
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:19.7.0 npm install
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:19.7.0 npm run build

js-libp2p-${commitSha}: js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

js-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"

clean:
	rm -rf js-libp2p-*.zip
	rm -rf js-libp2p-*

.PHONY: all clean perf
