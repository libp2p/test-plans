GO_FILES := $(wildcard *.go)

all: perf

perf: $(GO_FILES)
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp -e GOCACHE=/usr/src/myapp/.cache golang:1.20 go build -o perf .

clean:
	rm perf

.PHONY: all
