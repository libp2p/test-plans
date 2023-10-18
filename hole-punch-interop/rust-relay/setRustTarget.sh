#!/bin/bash

# Translate Docker platform format to Rust target format
case "$(echo $1 | cut -d/ -f2)" in
    "amd64") RUST_TARGET="x86_64-unknown-linux-musl";;
    "arm64") RUST_TARGET="aarch64-unknown-linux-gnu";;
    *) echo "Unsupported architecture: $1" >&2; exit 1;;
esac

# Export the RUST_TARGET value so it's available in subsequent RUN instructions
echo "export RUST_TARGET=${RUST_TARGET}" >> /etc/environment
