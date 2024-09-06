DOCKER_IMAGE := node:20-alpine
DOCKER_RUN := docker run --rm -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp $(DOCKER_IMAGE)

all: perf

perf:
	npm ci
	sudo npx playwright install-deps

clean:
	rm -rf node_modules

.PHONY: all clean perf
