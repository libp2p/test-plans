GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
RUST_CHROMIUM_SUBDIRS := $(wildcard impl/rust-chromium/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JVM_SUBDIRS := $(wildcard impl/jvm/*/.)
PYTHON_SUBDIRS := $(wildcard impl/python/*/.)
DOTNET_SUBDIRS := $(wildcard impl/dotnet/*/.)
C_SUBDIRS := $(wildcard impl/c/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(PYTHON_SUBDIRS) $(DOTNET_SUBDIRS) $(C_SUBDIRS)

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
$(PYTHON_SUBDIRS):
	$(MAKE) -C $@
$(C_SUBDIRS):
	$(MAKE) -C $@
$(DOTNET_SUBDIRS):
	$(MAKE) -C $@

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JVM_SUBDIRS) $(PYTHON_SUBDIRS) $(DOTNET_SUBDIRS) $(C_SUBDIRS) all
