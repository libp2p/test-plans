DOCKER_IMAGE := node:22-alpine
DOCKER_RUN := docker run --rm -v "$(shell pwd)":/usr/src/myapp -w /usr/src/myapp $(DOCKER_IMAGE)
DOCKER_RUN_LIBP2P := docker run --rm -v "$(shell pwd)/libp2p":/usr/src/myapp/libp2p -w /usr/src/myapp/libp2p $(DOCKER_IMAGE)

all: perf

perf:
	$(DOCKER_RUN_LIBP2P) npm ci
	$(DOCKER_RUN_LIBP2P) npm run build
	$(DOCKER_RUN) npm ci

clean:
	rm -rf node_modules

.PHONY: all clean perf
