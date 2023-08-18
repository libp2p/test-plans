NPM_PACKAGE_VERSION := 1.1.1
NPM_PACKAGE := @libp2p/perf
NPM_PACKAGE_NAME := $(NPM_PACKAGE)@$(NPM_PACKAGE_VERSION)

SOURCE_DIR := js-libp2p-protocol-perf

DOCKER_IMAGE := node:18.17.1
DOCKER_RUN := docker run --rm -v "$(shell pwd)/$(SOURCE_DIR)":/usr/src/myapp -w /usr/src/myapp $(DOCKER_IMAGE)

all: perf

perf:
	mkdir -p $(SOURCE_DIR)
	$(DOCKER_RUN) npm install $(NPM_PACKAGE_NAME)

clean: rm -rf js-libp2p-*

.PHONY: all clean perf install_node
