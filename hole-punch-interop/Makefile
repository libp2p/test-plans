RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)
RELAY_SUBDIRS := $(wildcard relay/*/.)

all: router $(RELAY_SUBDIRS) $(RUST_SUBDIRS) $(GO_SUBDIRS)
router:
	$(MAKE) -C router
$(RELAY_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
clean:
	for d in router $(RELAY_SUBDIRS) $(RUST_SUBDIRS) $(GO_SUBDIRS); do $(MAKE) -C $$d clean; done

.PHONY: router all $(RELAY_SUBDIRS) $(RUST_SUBDIRS) $(GO_SUBDIRS)
