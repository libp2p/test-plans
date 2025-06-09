all: perf

perf: perf.nim
	docker run --rm \
            -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp nimlang/nim:2.2.0 \
            sh -c ' \
            nimble install -y --depsOnly  && \
            nim c --threads:off --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:chronicles_log_level=NONE -d:release perf.nim && \
            chown -R $(shell id -u):$(shell id -g) .'

clean:
	rm -f perf

.PHONY: all clean