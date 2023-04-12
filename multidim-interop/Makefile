GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/nim/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS)
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


.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) all
