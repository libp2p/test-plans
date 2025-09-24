GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
RUST_CHROMIUM_SUBDIRS := $(wildcard impl/rust-chromium/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JAVA_SUBDIRS := $(wildcard impl/java/*/.)
PYTHON_SUBDIRS := $(wildcard impl/python/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(PYTHON_SUBDIRS)
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
$(JAVA_SUBDIRS):
	$(MAKE) -C $@
$(PYTHON_SUBDIRS):
	$(MAKE) -C $@

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(PYTHON_SUBDIRS) all
