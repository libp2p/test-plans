RUST_SUBDIRS := $(wildcard impl/rust/*/.)

all: rust-relay router $(RUST_SUBDIRS) test
rust-relay:
	$(MAKE) -C rust-relay
router:
	$(MAKE) -C router
$(RUST_SUBDIRS):
	$(MAKE) -C $@
results.csv: $(wildcard src/*.ts)
	npm run test
test: results.csv
clean:
	$(MAKE) -C rust-relay clean
	$(MAKE) -C router clean
	$(MAKE) -C $(RUST_SUBDIRS) clean
	rm results.csv

.PHONY: rust-relay router all $(RUST_SUBDIRS) test
