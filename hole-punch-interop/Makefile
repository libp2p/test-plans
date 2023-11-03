RUST_SUBDIRS := $(wildcard impl/rust/*/.)
GO_SUBDIRS := $(wildcard impl/go/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)

# Combine all sub-directory lists into a single list
ALL_SUBDIRS := $(RUST_SUBDIRS) $(GO_SUBDIRS) $(NIM_SUBDIRS)

all: rust-relay router $(ALL_SUBDIRS)

rust-relay:
	$(MAKE) -C rust-relay

router:
	$(MAKE) -C router

$(ALL_SUBDIRS):
	$(MAKE) -C $@

clean:
	$(MAKE) -C rust-relay clean
	$(MAKE) -C router clean
	for dir in $(ALL_SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done

.PHONY: rust-relay router all $(ALL_SUBDIRS) clean
