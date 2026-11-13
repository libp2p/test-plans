RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)

all: $(RUST_SUBDIRS) $(GO_SUBDIRS) $(JS_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(JS_SUBDIRS):
	$(MAKE) -C $@
clean:
	@set -e; \
	for dir in $(RUST_SUBDIRS) $(GO_SUBDIRS) $(JS_SUBDIRS); do \
		$(MAKE) -C "$$dir" clean; \
	done

.PHONY: all $(RUST_SUBDIRS) $(GO_SUBDIRS) $(JS_SUBDIRS)
