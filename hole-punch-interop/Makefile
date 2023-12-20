RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)

all: rust-relay router $(RUST_SUBDIRS) $(GO_SUBDIRS)
rust-relay:
	$(MAKE) -C rust-relay
router:
	$(MAKE) -C router
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
clean:
	$(MAKE) -C rust-relay clean
	$(MAKE) -C router clean
	$(MAKE) -C $(RUST_SUBDIRS) clean
	$(MAKE) -C $(GO_SUBDIRS) clean

.PHONY: rust-relay router all $(RUST_SUBDIRS) $(GO_SUBDIRS)
