GO_SUBDIRS := $(wildcard go-libp2p/*/.)
RUST_SUBDIRS := $(wildcard rust-libp2p/*/.)
RUST_QUINN_SUBDIRS := $(wildcard rust-libp2p-quinn/*/.)
HTTPS_SUBDIRS := $(wildcard https/*/.)
QUIC_GO_SUBDIRS := $(wildcard quic-go/*/.)
NIM_SUBDIRS := $(wildcard nim-libp2p/*/.)

all: $(RUST_SUBDIRS) $(RUST_QUINN_SUBDIRS) $(GO_SUBDIRS) $(HTTPS_SUBDIRS) $(QUIC_GO_SUBDIRS)
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(RUST_QUINN_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(HTTPS_SUBDIRS):
	$(MAKE) -C $@
$(QUIC_GO_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@

clean: $(RUST_SUBDIRS:%=%clean) $(RUST_QUINN_SUBDIRS:%=%clean) $(GO_SUBDIRS:%=%clean) $(HTTPS_SUBDIRS:%=%clean) $(QUIC_GO_SUBDIRS:%=%clean) $(NIM_SUBDIRS:%=%clean)

%clean:
	$(MAKE) -C $* clean

.PHONY: $(RUST_SUBDIRS) $(RUST_QUINN_SUBDIRS) $(GO_SUBDIRS) $(HTTPS_SUBDIRS) $(QUIC_GO_SUBDIRS) $(QUIC_GO_SUBDIRS) $(NIM_SUBDIRS) all clean
