commitSha := b1d89bda6c7952b7d60f560894aadc1544cc53ce

all: perf

perf: js-libp2p-${commitSha}/packages/perf
      cp ./js-libp2p-${commitSha}/packages/perf .

js-libp2p-${commitSha}/packages/perf: js-libp2p-${commitSha}
	docker run --rm --use "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/js-libp2p-${commitSha}":/usr/src/myapp -w /usr/src/myapp node:18.17.0 npm run build

js-libp2p-${commitSha}: js-libp2p-${commitSha}.zip
	unzip -o js-libp2p-${commitSha}.zip

js-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/libp2p/js-libp2p/archive/${commitSha}.zip"

clean:
	rm -rf js-libp2p-*.zip
	rm -rf js-libp2p-*
	rm perf

.PHONY: all clean
