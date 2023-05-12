commitSha := b3ed7966a563d528b7aa19265cbca929bf2bc73f

all: perf

perf: perf-${commitSha}
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/perf-${commitSha}":/usr/src/myapp -w /usr/src/myapp -e GOCACHE=/usr/src/myapp/.cache golang:1.20 go build -o perf cmd/main.go
	cp perf-${commitSha}/perf .

perf-${commitSha}: perf-${commitSha}.zip
	unzip -o perf-${commitSha}.zip

perf-${commitSha}.zip:
	# TODO: Depend on upstream, not mxinden
	wget -O $@ "https://github.com/mxinden/perf/archive/${commitSha}.zip"

clean:
	rm perf-*.zip
	rm -rf perf-*
	rm perf

.PHONY: clean


