GO_SUBDIRS := $(wildcard go-libp2p/*/.)
RUST_SUBDIRS := $(wildcard rust-libp2p/*/.)
HTTPS_SUBDIRS := $(wildcard https/*/.)
QUIC_GO_SUBDIRS := $(wildcard quic-go/*/.)
JS_SUBDIRS := $(wildcard js-libp2p/*/.)

all: $(RUST_SUBDIRS) $(GO_SUBDIRS) $(HTTPS_SUBDIRS) $(QUIC_GO_SUBDIRS) $(JS_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(HTTPS_SUBDIRS):
	$(MAKE) -C $@
$(QUIC_GO_SUBDIRS):
	$(MAKE) -C $@
$(JS_SUBDIRS):
	$(MAKE) -C $@

clean: $(RUST_SUBDIRS:%=%clean) $(GO_SUBDIRS:%=%clean) $(HTTPS_SUBDIRS:%=%clean) $(QUIC_GO_SUBDIRS:%=%clean) $(JS_SUBDIRS:%=%clean)

%clean:
	$(MAKE) -C $* clean

.PHONY: $(RUST_SUBDIRS) $(GO_SUBDIRS) $(HTTPS_SUBDIRS) $(QUIC_GO_SUBDIRS) $(JS_SUBDIRS) all clean
