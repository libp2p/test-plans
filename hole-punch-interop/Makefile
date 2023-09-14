RUST_SUBDIRS := $(wildcard impl/rust/*/.)

all: rust-relay router $(RUST_SUBDIRS)
rust-relay:
	$(MAKE) -C rust-relay
router:
	$(MAKE) -C router
$(RUST_SUBDIRS):
	$(MAKE) -C $@

.PHONY: rust-relay router all $(RUST_SUBDIRS)
