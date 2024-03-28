RUST_SUBDIRS := $(wildcard rust/*/.)

all: $(RUST_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@


.PHONY: $(RUST_SUBDIRS)
