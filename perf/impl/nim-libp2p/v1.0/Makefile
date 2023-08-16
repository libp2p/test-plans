image_name := nim-v1.0
commitSha := e03547ea3e2f0372c540c586e993803299d3c4b6

all: perf

perf: perf.nim nim-libp2p
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp nimlang/nim:1.6.10 sh -c "cd nim-libp2p && nimble install_pinned && cd - && nim c --NimblePath:nim-libp2p/nimbledeps/pkgs -p:nim-libp2p -d:chronicles_log_level=WARN --threads:off -d:release perf.nim"

nim-libp2p: nim-libp2p-${commitSha}
	rm -rf nim-libp2p
	ln -s nim-libp2p-${commitSha} nim-libp2p

nim-libp2p-${commitSha}: nim-libp2p-${commitSha}.zip
	unzip -o nim-libp2p-${commitSha}.zip

nim-libp2p-${commitSha}.zip:
	wget -O $@ "https://github.com/status-im/nim-libp2p/archive/${commitSha}.zip"
clean:
	rm -f perf
	rm -f nim-libp2p
	rm -rf nim-libp2p-${commitSha}
	rm -f nim-libp2p-${commitSha}.zip
