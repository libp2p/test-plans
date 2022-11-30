GO_SUBDIRS := $(wildcard go/*/.)

all: $(GO_SUBDIRS) rust/.
$(GO_SUBDIRS):
	$(MAKE) -C $@
rust/.:
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) rust/.