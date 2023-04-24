GO_SUBDIRS := $(wildcard impl/go/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
HTTPS_SUBDIRS := $(wildcard impl/https/.)

all: $(GO_SUBDIRS) $(RUST_SUBDIRS) $(ZIG_SUBDIRS) $(HTTPS_SUBDIRS)
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(ZIG_SUBDIRS):
	$(MAKE) -C $@
$(HTTPS_SUBDIRS):
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) $(RUST_SUBDIRS) $(ZIG_SUBDIRS) $(HTTPS_SUBDIRS) all
