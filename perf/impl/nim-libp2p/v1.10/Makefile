all: perf

# `nim c` command uses flags to:
#  - minimize output while compile - to reduce log output in the ci that runs perf benchmarking
#  - optimize for speed - to have the best possible performance

perf: perf.nim
	docker run --rm \
            -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp nimlang/nim:2.2.0 \
            sh -c ' \
            nimble install -y --depsOnly && \
            nim c --hints:off --verbosity:0 --warning[all]:off --threads:off --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:chronicles_enabled=off -d:release -d:danger -d:lto --opt:speed --stacktrace:off perf.nim && \
            chown -R $(shell id -u):$(shell id -g) .'

clean:
	rm -f perf

.PHONY: all clean