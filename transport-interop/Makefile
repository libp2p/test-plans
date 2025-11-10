GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
CHROMIUM_RUST_SUBDIRS := $(wildcard impl/chromium-rust/*/.)
# Exclude nim/v1.10 due to Dockerfile dependency issues (Nim version mismatch)
NIM_SUBDIRS := $(filter-out impl/nim/v1.10/.,$(wildcard impl/nim/*/.))
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JVM_SUBDIRS := $(wildcard impl/jvm/*/.)
PYTHON_SUBDIRS := $(wildcard impl/python/*/.)
DOTNET_SUBDIRS := $(wildcard impl/dotnet/*/.)
C_SUBDIRS := $(wildcard impl/c/*/.)
ETH_P2P_Z_SUBDIRS := $(wildcard impl/eth-p2p-z/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(CHROMIUM_RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(PYTHON_SUBDIRS) $(DOTNET_SUBDIRS) $(C_SUBDIRS) $(ETH_P2P_Z_SUBDIRS)

$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(CHROMIUM_RUST_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@
$(ZIG_SUBDIRS):
	$(MAKE) -C $@
$(JVM_SUBDIRS):
	$(MAKE) -C $@
$(PYTHON_SUBDIRS):
	$(MAKE) -C $@
$(C_SUBDIRS):
	$(MAKE) -C $@
$(DOTNET_SUBDIRS):
	$(MAKE) -C $@
$(ETH_P2P_Z_SUBDIRS):
	$(MAKE) -C $@

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(CHROMIUM_RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(PYTHON_SUBDIRS) $(DOTNET_SUBDIRS) $(C_SUBDIRS) $(ETH_P2P_Z_SUBDIRS) all
