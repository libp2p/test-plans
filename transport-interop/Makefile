GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
RUST_CHROMIUM_SUBDIRS := $(wildcard impl/rust-chromium/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JVM_SUBDIRS := $(wildcard impl/jvm/*/.)
ETH_P2P_Z_SUBDIRS := $(wildcard impl/eth-p2p-z/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(ETH_P2P_Z_SUBDIRS)

$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(RUST_CHROMIUM_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@
$(ZIG_SUBDIRS):
	$(MAKE) -C $@
$(JVM_SUBDIRS):
	$(MAKE) -C $@
$(ETH_P2P_Z_SUBDIRS):
	$(MAKE) -C $@

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(ETH_P2P_Z_SUBDIRS) all
