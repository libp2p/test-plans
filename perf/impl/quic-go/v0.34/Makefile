commitSha := 3a12ea9207e40de20533b0a6aa2e40e3727aa796

all: perf

perf: perf-${commitSha}
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/perf-${commitSha}":/usr/src/myapp -w /usr/src/myapp -e GOCACHE=/usr/src/myapp/.cache golang:1.20 go build -o perf cmd/main.go
	cp perf-${commitSha}/perf .

perf-${commitSha}: perf-${commitSha}.zip
	unzip -o perf-${commitSha}.zip

perf-${commitSha}.zip:
	# TODO: revert
	wget -O $@ "https://github.com/mxinden/perf/archive/${commitSha}.zip"

clean:
	rm perf-*.zip
	rm -rf perf-*
	rm perf
	rm .cache
	rm v0.27

.PHONY: all clean
