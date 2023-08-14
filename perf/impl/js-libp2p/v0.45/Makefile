commitSha := bf087d9f7b868dd1e235828e4aae0160c7afbc5c

all: perf

perf: js-libp2p-${commitSha}
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:18.14.2 npm install
	docker run --rm -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:18.14.2 npm run build

js-libp2p-${commitSha}: js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

js-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"

clean:
	rm -rf js-libp2p-*.zip
	rm -rf js-libp2p-*

.PHONY: all clean perf
