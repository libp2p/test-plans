RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)
PYTHON_SUBDIRS := $(wildcard impl/python/*/.)

all: rust-relay router $(RUST_SUBDIRS) $(GO_SUBDIRS) $(PYTHON_SUBDIRS)
rust-relay:
	$(MAKE) -C rust-relay
router:
	$(MAKE) -C router
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(PYTHON_SUBDIRS):
	$(MAKE) -C $@
clean:
	$(MAKE) -C rust-relay clean
	$(MAKE) -C router clean
	$(MAKE) -C $(RUST_SUBDIRS) clean
	$(MAKE) -C $(GO_SUBDIRS) clean
	$(MAKE) -C $(PYTHON_SUBDIRS) clean

.PHONY: rust-relay router all $(RUST_SUBDIRS) $(GO_SUBDIRS) $(PYTHON_SUBDIRS)
