GO_SUBDIRS := $(wildcard go-libp2p/*/.)
RUST_SUBDIRS := $(wildcard rust-libp2p/*/.)
HTTPS_SUBDIRS := $(wildcard https/*/.)

all: $(RUST_SUBDIRS) $(GO_SUBDIRS) $(HTTPS_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(HTTPS_SUBDIRS):
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) $(RUST_SUBDIRS) $(HTTPS_SUBDIRS) all
