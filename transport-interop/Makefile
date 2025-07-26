# To build in parallel, run: make all-parallel -j$(nproc) or make parallel -j$(nproc)
# where $(nproc) is the number of CPU cores available
# 
# make all          - builds everything sequentially (original behavior)
# make all-parallel - builds everything in parallel (including within subdirectories)

GO_SUBDIRS := $(wildcard impl/go/*/.)
JS_SUBDIRS := $(wildcard impl/js/*/.)
RUST_SUBDIRS := $(wildcard impl/rust/*/.)
RUST_CHROMIUM_SUBDIRS := $(wildcard impl/rust-chromium/*/.)
NIM_SUBDIRS := $(wildcard impl/nim/*/.)
ZIG_SUBDIRS := $(wildcard impl/zig/*/.)
JAVA_SUBDIRS := $(wildcard impl/java/*/.)
PYTHON_SUBDIRS := $(wildcard impl/python/*/.)

# Create parallel versions of subdirectory lists
GO_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(GO_SUBDIRS))
JS_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(JS_SUBDIRS))
RUST_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(RUST_SUBDIRS))
RUST_CHROMIUM_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(RUST_CHROMIUM_SUBDIRS))
NIM_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(NIM_SUBDIRS))
ZIG_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(ZIG_SUBDIRS))
JAVA_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(JAVA_SUBDIRS))
PYTHON_SUBDIRS_PARALLEL := $(addsuffix -parallel,$(PYTHON_SUBDIRS))

# Extract the number of jobs from MAKEFLAGS or use all available cores
JOBS := $(filter -j%,$(MAKEFLAGS))
ifeq ($(JOBS),)
    JOBS := -j$(shell nproc)
endif

# Original sequential build (default target)
all: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(PYTHON_SUBDIRS)

# New parallel build target - uses separate parallel targets
all-parallel:
	$(MAKE) $(JOBS) $(GO_SUBDIRS_PARALLEL) $(JS_SUBDIRS_PARALLEL) $(RUST_SUBDIRS_PARALLEL) $(RUST_CHROMIUM_SUBDIRS_PARALLEL) $(NIM_SUBDIRS_PARALLEL) $(ZIG_SUBDIRS_PARALLEL) $(JAVA_SUBDIRS_PARALLEL) $(PYTHON_SUBDIRS_PARALLEL)

# Parallel target - same as 'all-parallel' but explicitly indicates parallel execution
parallel: all-parallel

# Help target
help:
	@echo "Available targets:"
	@echo "  all          - builds everything sequentially (original behavior)"
	@echo "  all-parallel - builds everything in parallel (including within subdirectories)"
	@echo "  parallel     - same as all-parallel"
	@echo "  clean        - remove all Docker images and build artifacts"
	@echo "  help         - show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make all                    # sequential build"
	@echo "  make all-parallel           # parallel build using all cores"
	@echo "  make all-parallel -j4       # parallel build using 4 cores"
	@echo "  make parallel -j$(shell nproc)  # parallel build using all cores"
	@echo "  make clean                  # remove all Docker images"

# Sequential builds (original behavior)
$(JS_SUBDIRS):
	$(MAKE) -C $@
$(GO_SUBDIRS):
	$(MAKE) -C $@
$(RUST_SUBDIRS):
	$(MAKE) -C $@
$(RUST_CHROMIUM_SUBDIRS):
	$(MAKE) -C $@
$(NIM_SUBDIRS):
	$(MAKE) -C $@
$(ZIG_SUBDIRS):
	$(MAKE) -C $@
$(JAVA_SUBDIRS):
	$(MAKE) -C $@
$(PYTHON_SUBDIRS):
	$(MAKE) -C $@

# Parallel builds (new behavior) - run subdirectories in parallel
$(JS_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(GO_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(RUST_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(RUST_CHROMIUM_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(NIM_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(ZIG_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(JAVA_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)
$(PYTHON_SUBDIRS_PARALLEL):
	$(MAKE) -C $(subst -parallel,,$@)

# Clean target - remove all Docker images and build artifacts
clean:
	@echo "Cleaning up Docker images and build artifacts..."
	@echo "Removing transport-interop Docker images..."
	@docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(transport-interop|python-v0\.2\.9|go-v0\.[0-9]+|js-v[0-9]+|rust-v[0-9]+|nim-v[0-9]+|zig-v[0-9]+|java-v[0-9]+)" | awk '{print $$1}' | xargs -r docker rmi -f 2>/dev/null || true
	@echo "Removing any remaining containers..."
	@docker ps -a --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
	@echo "Cleaning up build artifacts in subdirectories..."
	@find impl -name "image.json" -delete 2>/dev/null || true
	@find impl -name "force-rebuild" -delete 2>/dev/null || true
	@echo "Cleanup complete!"

.PHONY: $(GO_SUBDIRS) $(JS_SUBDIRS) $(RUST_SUBDIRS) $(RUST_CHROMIUM_SUBDIRS) $(NIM_SUBDIRS) $(ZIG_SUBDIRS) $(JAVA_SUBDIRS) $(PYTHON_SUBDIRS) all all-parallel parallel help clean
.PHONY: $(GO_SUBDIRS_PARALLEL) $(JS_SUBDIRS_PARALLEL) $(RUST_SUBDIRS_PARALLEL) $(RUST_CHROMIUM_SUBDIRS_PARALLEL) $(NIM_SUBDIRS_PARALLEL) $(ZIG_SUBDIRS_PARALLEL) $(JAVA_SUBDIRS_PARALLEL) $(PYTHON_SUBDIRS_PARALLEL)
