commitSha := 5ef52595604bee86e75d9692d08441ed6c208668

all: perf

perf: perf-${commitSha}
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)/perf-${commitSha}":/usr/src/myapp -w /usr/src/myapp -e GOCACHE=/usr/src/myapp/.cache golang:1.20 go build -o perf cmd/main.go
	cp perf-${commitSha}/perf .

perf-${commitSha}: perf-${commitSha}.zip
	unzip -o perf-${commitSha}.zip

perf-${commitSha}.zip:
	wget -O $@ "https://github.com/quic-go/perf/archive/${commitSha}.zip"

clean:
	rm perf-*.zip
	rm -rf perf-*
	rm perf

.PHONY: clean


