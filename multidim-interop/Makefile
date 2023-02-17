GO_SUBDIRS := $(wildcard go/*/.)
JS_SUBDIRS := $(wildcard js/*/.)
RUST_SUBDIRS := $(wildcard rust/*/.)
NIM_SUBDIRS := $(wildcard nim/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS)
$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(NIM_SUBDIRS) all
