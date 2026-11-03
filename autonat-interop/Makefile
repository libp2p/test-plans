GO_SUBDIRS := $(wildcard impl/go/*/.)

all: $(GO_SUBDIRS)
$(GO_SUBDIRS):
	$(MAKE) -C $@
clean:
	$(MAKE) -C $(GO_SUBDIRS) clean

.PHONY: all $(GO_SUBDIRS)
