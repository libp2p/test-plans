RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)

all: $(RUST_SUBDIRS) $(GO_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
clean:
	$(MAKE) -C $(RUST_SUBDIRS) clean
	$(MAKE) -C $(GO_SUBDIRS) clean

.PHONY: all $(RUST_SUBDIRS) $(GO_SUBDIRS)
