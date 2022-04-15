#! /usr/bin/env bash
set -e
set -o pipefail
set -x

# TODO: use INPUT_TESTPLAN and INPUT_TESTCASE

if [ -z "$GO_LIBP2P_REF" ]; then
    echo "Missing GO_LIBP2P_REF, using default"
else
    pushd compatibility/compatibility-go
    # TODO: do we want something like a coma separated list of replacement?
    # TODO: is there a more idiomatic way to apply the replace?
    # something like `go mod edit -replace github.com/libp2p/go-libp2p=github.com/libp2p/go-libp2p@${GO_LIBP2P_REF}`
    go get github.com/libp2p/go-libp2p@${GO_LIBP2P_REF}
    go mod tidy
    popd
fi

if [ -z "$RUST_LIBP2P_REF" ]; then
    echo "Missing RUST_LIBP2P_REF, using default"
else
    pushd compatibility/compatibility-rust
    # TODO: is there a more idiomatic way to apply the replace?
    cat <<EOF >> ./Cargo.toml

[patch.crates-io]
libp2p = { git = 'https://github.com/libp2p/rust-libp2p', rev = '${RUST_LIBP2P_REF}' }
EOF
    popd
fi

# Build every plan and store the generated artifact.
# similar to https://github.com/testground/testground/blob/master/integration_tests/01_k8s_kind_placebo_ok.sh

testground plan import --from ./compatibility/compatibility-go
testground build single --wait \
    --builder docker:go \
    --plan compatibility-go | tee build.go.out
export ARTIFACT_GO=$(awk -F\" '/generated build artifact/ {print $8}' <build.go.out)

testground plan import --from ./compatibility/compatibility-rust
testground build single --wait \
    --builder docker:generic \
    --plan compatibility-rust | tee build.rust.out
export ARTIFACT_RUST=$(awk -F\" '/generated build artifact/ {print $8}' <build.rust.out)

envsubst < "./compatibility/composition.template.toml" > "./compatibility/composition.toml"
