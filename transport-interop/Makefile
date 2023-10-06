GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JAVA_SUBDIRS := $(wildcard impl/java/*/.)
DOTNET_SUBDIRS := $(wildcard impl/dotnet/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(DOTNET_SUBDIRS)
$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@
$(ZIG_SUBDIRS):
	$(MAKE) -C $@
$(JAVA_SUBDIRS):
	$(MAKE) -C $@
$(DOTNET_SUBDIRS):
	$(MAKE) -C $@

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(DOTNET_SUBDIRS) all
