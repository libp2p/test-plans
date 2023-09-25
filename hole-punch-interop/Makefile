RUST_SUBDIRS := $(wildcard impl/rust/*/.)

all: rust-relay router $(RUST_SUBDIRS)
rust-relay:
	$(MAKE) -C rust-relay
router:
	$(MAKE) -C router
$(RUST_SUBDIRS):
	$(MAKE) -C $@
clean:
	$(MAKE) -C rust-relay clean
	$(MAKE) -C router clean
	$(MAKE) -C $(RUST_SUBDIRS) clean

.PHONY: rust-relay router all $(RUST_SUBDIRS)
