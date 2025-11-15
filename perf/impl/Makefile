JS_SUBDIRS := $(wildcard js-libp2p/*/.)

all:$(JS_SUBDIRS)

$(JS_SUBDIRS):
	$(MAKE) -C $@

js-libp2p: $(JS_SUBDIRS)

clean: $(JS_SUBDIRS:%=%clean)

%clean:
	$(MAKE) -C $* clean

.PHONY: $(JS_SUBDIRS) all clean
