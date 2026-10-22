# Pinned py-libp2p tree (same idea as transport-interop Python image).
# Includes yamux window + perf fixes from https://github.com/libp2p/py-libp2p/pull/1258 (tip at pin time); update when merged to main.
commitSha := 731c3c787d3e98e380263943132d301c1be8dcd5

# Use 3.11–3.12 for libp2p deps (e.g. coincurve wheels); avoid 3.14+ where builds fail.
PYTHON_FOR_VENV ?= python3.12

LIBP2P_DIR := py-libp2p-$(commitSha)
VENV := .venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip

all: $(PYTHON) perf_cli.py
	chmod +x perf

$(LIBP2P_DIR).zip:
	wget -O $@ "https://github.com/libp2p/py-libp2p/archive/$(commitSha).zip"

$(LIBP2P_DIR): $(LIBP2P_DIR).zip
	unzip -o $<
	touch $@

$(PYTHON): $(LIBP2P_DIR)
	$(PYTHON_FOR_VENV) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install "./$(LIBP2P_DIR)/"

clean:
	rm -rf $(VENV) $(LIBP2P_DIR).zip $(LIBP2P_DIR)

.PHONY: all clean
