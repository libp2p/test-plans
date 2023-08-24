RUST_SUBDIRS := $(wildcard rust-libp2p/*/.)
HTTPS_SUBDIRS := $(wildcard https/*/.)

all: $(RUST_SUBDIRS) $(HTTPS_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(HTTPS_SUBDIRS):
	$(MAKE) -C $@

clean: $(RUST_SUBDIRS:%=%clean) $(HTTPS_SUBDIRS:%=%clean)

%clean:
	$(MAKE) -C $* clean

.PHONY: $(RUST_SUBDIRS) $(HTTPS_SUBDIRS)
