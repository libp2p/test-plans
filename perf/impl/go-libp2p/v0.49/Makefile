GO_FILES := $(wildcard *.go)

all: perf

perf: $(GO_FILES)
	docker run --rm --user "$(shell id -u):$(shell id -g)" -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp -e GOCACHE=/usr/src/myapp/.cache golang:$(shell awk '/^go [0-9]+\.[0-9]+$$/ {print $$2}' go.mod) go build -o perf .

clean:
	rm -r .cache
	rm perf

.PHONY: all clean
