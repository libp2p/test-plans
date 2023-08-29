# Interoperability/end to end test-plans & performance benchmarking for libp2p

[![Interop Dashboard](https://github.com/libp2p/test-plans/workflows/libp2p%20multidimensional%20interop%20test/badge.svg?branch=master)](https://github.com/libp2p/test-plans/actions/runs/5982868095/attempts/1#summary-16232428622)

[![Made by Protocol Labs](https://img.shields.io/badge/made%20by-Protocol%20Labs-blue.svg?style=flat-square)](http://protocol.ai)

This repository contains:
* interoperability and end to end tests for libp2p modules across different implementations and versions
* components to run performance benchmarks for different libp2p implementations

## Multidimensional Interop
### Specs

Please see our first specification for interoperability tests between transports, multiplexers, and secure channels here: [Interoperability Test Specs](./multidim-interop/README.md)

More specs to come soon!

## History

These test-plans historically used Testground. To read why we're now using `docker compose` instead please see: [Why we're moving away from Testground](https://github.com/libp2p/test-plans/issues/103)

## Performance Benchmarking

Please see the [benchmarking README](./perf#libp2p-performance-benchmarking).

## Roadmap

Our roadmap for test-plans can be found here: https://github.com/libp2p/test-plans/blob/master/ROADMAP.md

It represents current projects the test-plans maintainers are focused on and provides an estimation of completion targets.
It is complementary to those of [go-libp2p](https://github.com/libp2p/go-libp2p/blob/master/ROADMAP.md), [rust-libp2p](https://github.com/libp2p/rust-libp2p/blob/master/ROADMAP.md), [js-libp2p](https://github.com/libp2p/js-libp2p/blob/master/ROADMAP.md), and the [overarching libp2p project roadmap](https://github.com/libp2p/specs/blob/master/ROADMAP.md).

## License

Dual-licensed: [MIT](./LICENSE-MIT), [Apache Software License v2](./LICENSE-APACHE), by way of the
[Permissive License Stack](https://protocol.ai/blog/announcing-the-permissive-license-stack/).
