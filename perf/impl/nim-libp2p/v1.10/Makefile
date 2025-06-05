# commit corresponds to v1.10.1 version of nim-libp2p
commitSha := cd60b254a0700b0daac7a6cb2c0c48860b57c539

all: perf

perf: perf.nim nim-libp2p
	docker run --rm \
            -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp nimlang/nim:2.2.0 \
            sh -c ' \
			  rm nimlibp2p && \
			  ln -s nim-libp2p nimlibp2p && \
              cd nim-libp2p && \
              nimble install_pinned && cd ../ && \
			  nimble install -y --depsOnly  && \
              nim c --threads:off --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:chronicles_log_level=WARN -d:release perf.nim && \
              chown -R $(shell id -u):$(shell id -g) .'

nim-libp2p: nim-libp2p-${commitSha}
	rm -rf nim-libp2p
	ln -s nim-libp2p-${commitSha} nim-libp2p

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"

clean:
	rm -rf nim-libp2p
	rm -rf nim-libp2p-${commitSha}
	rm -rf nim-libp2p-${commitSha}.zip

.PHONY: all clean