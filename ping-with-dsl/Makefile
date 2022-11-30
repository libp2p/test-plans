GO_SUBDIRS := $(wildcard go/*/.)

all: $(GO_SUBDIRS) rust/.
$(GO_SUBDIRS):
	$(MAKE) -C $@

rust/.:
	$(MAKE) -C $@

.PHONY: all $(GO_SUBDIRS) rust/.
