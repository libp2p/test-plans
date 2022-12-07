# Testground test plans for libp2p

[![Made by Protocol Labs](https://img.shields.io/badge/made%20by-Protocol%20Labs-blue.svg?style=flat-square)](http://protocol.ai)
![Go version](https://img.shields.io/badge/go-%3E%3D1.14.0-blue.svg?style=flat-square)

This repository contains Testground test plans for libp2p components.

## Roadmap

Our roadmap for test-plans can be found here: https://github.com/libp2p/test-plans/blob/master/ROADMAP.md

It represents current projects the test-plans maintainers are focused on and provides an estimation of completion targets.
It is complementary to those of [go-libp2p](https://github.com/libp2p/go-libp2p/blob/master/ROADMAP.md), [rust-libp2p](https://github.com/libp2p/rust-libp2p/blob/master/ROADMAP.md), [js-libp2p](https://github.com/libp2p/js-libp2p/blob/master/ROADMAP.md), and the [overarching libp2p project roadmap](https://github.com/libp2p/specs/blob/master/ROADMAP.md).

## How to add a new version to ping/go

When a new version of libp2p is released, we want to make it permanent in the `ping/go` test folder.

1. In the `ping/_compositions/go.toml` file,
    - copy the `[master]` section and turn it into a `[[groups]]` item
    - update the `[master]` section with the future version
2. In the `ping/go` folder,
    - Add a new compatibility shim in `compat/` if needed, or add your new selector to the latest shim (see `compat/libp2p.v0.17.go` for example).
    - Create the new mod and sum files (`go.v0.21.mod` for example). Assuming you're updating from `v$A` to `v$B`, a simple way to do this is to:
        - `cp go.v$A.mod go.v$B.mod; cp go.v$A.sum go.v$B.sum`
        - `ln -s go.v$B.mod go.mod; ln -s go.v$B.sum go.sum` (you may also use this for local development, these files are ignored by git)
        - update the `go-libp2p` version, go version, and update the code if needed.
        - then `go get -tags v$B && go mod tidy`
3. Run the test on your machine
    - Do once, from the test-plans root: import the test-plans with `testground plan import --from ./ --name libp2p`
    - Run the test with `testground run composition -f ping/_compositions/go-cross-versions.toml --wait`

## How to add a new version to ping/rust

When a new version of libp2p is released, we want to make it permanent in the `ping/rust` test folder.

1. In the `ping/_compositions/rust.toml` file,
    - Copy the latest `[[groups]]` section and update it's `Id` and `BinaryName` accordingly.
2. In the `ping/rust` folder,
    - `Cargo.toml`: Add the newly released version as a crates.io dependency.
    - `Cargo.toml`: Update the `Next release` dependency to the latest `master` SHA.
    - `src/bin`: Add a new binary with the next released version.
3. Run the test on your machine
    - Do once, from the test-plans root: import the test-plans with `testground plan import --from ./ --name libp2p`
    - Run the test with `testground run composition -f ping/_compositions/rust-cross-versions.toml --wait`

## License

Dual-licensed: [MIT](./LICENSE-MIT), [Apache Software License v2](./LICENSE-APACHE), by way of the
[Permissive License Stack](https://protocol.ai/blog/announcing-the-permissive-license-stack/).
