RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)

all: $(RUST_SUBDIRS) $(GO_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
clean:
	@set -e; \
	for dir in $(RUST_SUBDIRS) $(GO_SUBDIRS); do \
		$(MAKE) -C "$$dir" clean; \
	done

.PHONY: all $(RUST_SUBDIRS) $(GO_SUBDIRS)
