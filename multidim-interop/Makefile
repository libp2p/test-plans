GO_SUBDIRS := $(wildcard go/*/.)
JS_SUBDIRS := $(wildcard js/*/.)

all: $(GO_SUBDIRS) $(JS_SUBDIRS)  rust/.
$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
rust/.:
	$(MAKE) -C $@


.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) rust/. all