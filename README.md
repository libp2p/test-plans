# Testground test plans for libp2p

[![Made by Protocol Labs](https://img.shields.io/badge/made%20by-Protocol%20Labs-blue.svg?style=flat-square)](http://protocol.ai)
![Go version](https://img.shields.io/badge/go-%3E%3D1.14.0-blue.svg?style=flat-square)

This repository contains Testground test plans for libp2p components.

## How to add a new version to ping/go

When a new version of libp2p is released, we want to make it permanent in the `ping/go` test folder.

1. In the `ping/_compositions/go-cross-versions.toml` file,
    - Find the group for the latest version (`v0.20` for example) and copy it into a new group (`v0.21` for example).
    - Update the `selectors` (go tags) and `modfile` options. Update the `build_base_image` if needed.
2. In the `ping/go` folder,
    - Add a new compatibility shim in `compat/` if needed, or add your new selector to the latest shim (see `compat/libp2p.v0.17.go` for example).
    - Create the new mod and sum files (`go.v0.21.mod` for example). Assuming you're updating from `v$A` to `v$B`, a simple way to do this is to:
        - `cp go.v$A.mod go.v$B.mod; cp go.v$A.sum go.v$B.sum`
        - `ln -s go.v$B.mod go.mod; ln -s go.v$B.sum go.sum` (you may also use this for local development, these files are ignored by git)
        - update the `go-libp2p` version, go version, and update the code if needed.
        - then `go get -tags v$B && go mod tidy`


## License

Dual-licensed: [MIT](./LICENSE-MIT), [Apache Software License v2](./LICENSE-APACHE), by way of the
[Permissive License Stack](https://protocol.ai/blog/announcing-the-permissive-license-stack/).
