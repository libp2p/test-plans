GO_SUBDIRS := $(wildcard go/*/.)

all: $(GO_SUBDIRS)
$(GO_SUBDIRS):
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) all