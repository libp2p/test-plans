DOCKER_IMAGE := node:20-alpine
DOCKER_RUN := docker run --rm -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp $(DOCKER_IMAGE)

all: perf

perf:
	$(DOCKER_RUN) npm ci

clean:
	rm -rf node_modules

.PHONY: all clean perf
