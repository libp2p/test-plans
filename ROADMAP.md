# test-plans roadmap Q4’22/Q1’23 <!-- omit in toc -->

```
Date: 2022-10-18
Status: Accepted
Notes: Internal test-plans stakeholders have aligned on this roadmap. Please add any feedback or questions in:
https://github.com/libp2p/test-plans/issues/58
```

## Table of Contents <!-- omit in toc -->

- [About the Roadmap](#about-the-roadmap)
  - [Vision](#vision)
  - [Sections](#sections)
- [🛣️ Milestones](#️-milestones)
  - [2022](#2022)
    - [Early Q4 (October)](#early-q4-october)
    - [Mid Q4 (November)](#mid-q4-november)
    - [End of Q4 (December)](#end-of-q4-december)
  - [2023](#2023)
    - [Early Q1 (January)](#early-q1-january)
    - [End of Q1 (March)](#end-of-q1-march)
  - [Up Next](#up-next)
- [📖 Appendix](#-appendix)
  - [A. Multi-dimensional Testing/Interop Visibility](#a-multi-dimensional-testinginterop-visibility)
    - [1. User configured interop tests & dashboard](#1-user-configured-interop-tests--dashboard)
    - [2. Interop test plans for all existing/developing libp2p transports](#2-interop-test-plans-for-all-existingdeveloping-libp2p-transports)
    - [3. Canonical interop tests & dashboard](#3-canonical-interop-tests--dashboard)
  - [B. Hardening test infrastructure](#b-hardening-test-infrastructure)
    - [1. Track test suite stability](#1-track-test-suite-stability)
    - [2. Design process for adding new tests](#2-design-process-for-adding-new-tests)
    - [3. Be the home for all interop tests](#3-be-the-home-for-all-interop-tests)
  - [C. Future-proof Benchmarking](#c-future-proof-benchmarking)
    - [1. Benchmarking using nix-builders](#1-benchmarking-using-nix-builders)
    - [2. Benchmarking using remote runners](#2-benchmarking-using-remote-runners)
  - [D. Expansive protocol test coverage](#d-expansive-protocol-test-coverage)
    - [1. DHT server mode scale test](#1-dht-server-mode-scale-test)
    - [2. AutoNat](#2-autonat)
    - [3. Hole Punching](#3-hole-punching)
    - [4. AutoRelay](#4-autorelay)
    - [5. Custom topologies](#5-custom-topologies)
    - [6. MTU Fixes](#6-mtu-fixes)

## About the Roadmap

### Vision
We, the maintainers, are committed to upholding libp2p's shared core tenets and ensuring libp2p implementations are: [**Secure, Stable, Specified, and Performant.**](https://github.com/libp2p/specs/blob/master/ROADMAP.md#core-tenets)

This roadmap is complementary to those of [go-libp2p](https://github.com/libp2p/go-libp2p/blob/master/ROADMAP.md), [rust-libp2p](https://github.com/libp2p/rust-libp2p/blob/master/ROADMAP.md), and [js-libp2p](https://github.com/libp2p/js-libp2p/blob/master/ROADMAP.md).

It aims to encompass the **stability** and **performance** tenets of the libp2p team.
Projects outlined here are shared priorities of the different implementations.

### Sections
This document consists of two sections: [Milestones](#️-milestones) and the [Appendix](#-appendix)

[Milestones](#️-milestones) is our best educated guess (not a hard commitment) around when we plan to ship the key features.
Where possible projects are broken down into discrete sub-projects e.g. project "A" may contain two sub-projects: A.1 and A.2

A project is signified as "complete" once all of it's sub-projects are shipped.

The [Appendix](#-appendix) section describes a project's high-level motivation, goals, and lists sub-projects.

Each Appendix header is linked to a GitHub Epic. Latest information on progress can be found in the Epics and child issues.

## 🛣️ Milestones

### 2022

#### Early Q4 (October)
- [A.1 User Configured Interop Tests & Dashboard](#1-user-configured-interop-tests--dashboard)

#### Mid Q4 (November)
- [A.2 Interop tests for all existing/developing libp2p transports](#2-interop-test-plans-for-all-existingdeveloping-libp2p-transports)
- [C.1 Benchmarking using nix-builders](#1-benchmarking-using-nix-builders)

#### End of Q4 (December)
- [A.3 Canonical Interop Tests & Dashboard](#3-canonical-interop-tests--dashboard)

### 2023

#### Early Q1 (January)

- [D.1 DHT Server Mode Scale Test](#1-dht-server-mode-scale-test)

#### End of Q1 (March)
- [C.2 Benchmarking using remote runners](#2-benchmarking-using-remote-runners)

### Up Next

## 📖 Appendix

**Projects are listed in descending priority.**

### [A. Multi-dimensional Testing/Interop Visibility](https://github.com/libp2p/test-plans/issues/53)
**Why:** libp2p supports a variety of transport protocols, muxers, & security protocols across implementations in different languages. Until we actually test them together, we can't guarantee implementation interoperability. We need to ensure and demonstrate that: interoperable features work with each other as expected and we don't introduce degradations that break interoperability in new releases.

**Goal:** libp2p implementers run tests across permutations of libp2p implementations, versions, and supported transports, muxers, and security protocols. Implementers and users can reference a single website with a dashboard to view the Pass/Fail/Implemented/Not Implemented results of multi-dimensional tests.

This effort depends on [Testground Milestone 1](https://github.com/testground/testground/blob/master/ROADMAP.md#1-bootstrap-libp2ps-interoperability-testing-story)

**How:**
#### [1. User configured interop tests & dashboard](https://github.com/libp2p/test-plans/issues/55)
Enable test-plans maintainers to define a configuration (of libp2p impls, versions, transports, expected RTT), run Testground tests per configuration, and retrieve resulting data in a standard format.
The test case results can be formatted as a "dashboard" (simple Markdown table of Pass/Fail results.)

#### [2. Interop test plans for all existing/developing libp2p transports](https://github.com/libp2p/test-plans/issues/61)
Using tooling from A.1, all features of go-libp2p, rust-libp2p, and js-libp2p that should be interoperable are tested (i.e. transports (TCP, QUIC, WebRTC, WebTransport), multiplexers (mplex, yamux), secure channels (TLS, Noise), etc.) across versions.

Features currently in development across implementations (like WebRTC in go-libp2p and rust-libp2p, or QUIC & TLS in rust-libp2p) are not merged without at least manually running these test suites.

Test suites are run in `libp2p/test-plans` CI and before releasing a version of go-libp2p,  rust-libp2p, and js-libp2p (GitHub workflow added so that these suites run against the `master` branch on a nightly basis (updating the status check.))

**Note:**
- Dependency on [C.1](#1-benchmarking-using-nix-builders) to run node.js-libp2p in Testground.
- Dependency on [testground/Investigate browser test support](https://github.com/testground/testground/issues/1386) to run interoperability test for js-libp2p WebRTC against Go and Rust.

#### [3. Canonical interop tests & dashboard](https://github.com/libp2p/test-plans/issues/62)
A comprehensive and canonical dashboard is generated and hosted in a publicly discoverable site that displays latest test suite results (Pass/Fail/Implemented/Not Implemented/Unimplementable) from a nightly CI run.
All permutations of libp2p implementations, versions, and supported transports, muxers, & security protocols should be visible.

An enhancement of A.1 to make it easier for users and implementers to see the full state of libp2p interoperability.

### B. Hardening test infrastructure

#### 1. Track test suite stability
<!-- TODO: Assign a quarter -->
<!-- TODO: Create issue -->
`libp2p/test-plans` maintainers have a straightforward way to track the test suite stability and performance.
- We can track the status of every test combination stability from the interop project itself
- We can easily measure the consequence (improvements) of a pull request to the libp2p/interop repository
- We are alerted when an interop test starts failing on one of our client repositories, and we can dispatch the alert to repo maintainers.

#### 2. Design process for adding new tests
<!-- TODO: Assign a quarter -->
<!-- TODO: Create issue -->
We have an explicit, working, Design Process for adding new tests
- The design is documented in `./DESIGN.md`.
- The design is followed by the team when we add new features.
- There is a clear path when it comes to testing new features. This might mean testing multiple `masters` against each other.

#### 3. Be the home for all interop tests
<!-- TODO: Assign a quarter -->
<!-- TODO: Create issue -->
We have ported the tests from `libp2p/interop`
- This repository implement tests `connect`, `dht`, `pubsub` ([ref](https://github.com/libp2p/interop/blob/ce0aa3749c9c53cf5ad53009b273847b94106d40/src/index.ts#L32-L35))
- At of writing (2022-09-27), it is disabled in `go-libp2p` ([ref](https://github.com/libp2p/go-libp2p/actions/workflows/interop.yml)), and it is used in `js-libp2p` ([ref](https://github.com/libp2p/js-libp2p/actions/runs/3111413168/jobs/5050929689)).


### [C. Future-proof Benchmarking](https://github.com/libp2p/test-plans/issues/63)
**Why**: For libp2p to be competitive, it needs to delivers comparable performance to widely used protocols on the internet, namely HTTP/2 and HTTP/3.

**Goal**: We have a test suite that runs libp2p transfers between nodes located at different locations all over the world, proving that libp2p is able to achieve performance on par with HTTP. The test suite is run on a continuous basis and results are published to a public performance dashboard.

#### [1. Benchmarking using nix-builders](https://github.com/testground/testground/pull/1425)
- [Benchmark go-libp2p, rust-libp2p, and go-libp2p](https://github.com/libp2p/test-plans/issues/27)
- [Specifically add js-libp2p-transfer-performance as a test-plan and CI job to benchmark transfer times across releases](https://github.com/libp2p/test-plans/issues/65) to catch issues like [#1342](https://github.com/libp2p/js-libp2p/issues/1342)
- (Dependency: remote machines need Nix installed)
#### [2. Benchmarking using remote runners](https://github.com/testground/testground/issues/1392)
Benchmarking using first class support for remote runners (using `remote:exec`) in Testground

### [D. Expansive protocol test coverage](https://github.com/libp2p/test-plans/issues/64)
**Why:** Having interoperability tests with lots of transports, encryption mechanisms, and stream muxers is great. However, we need to stay backwards-compatible with legacy libp2p releases, with other libp2p implementations, and less advanced libp2p stacks.

**Goal:** Expand beyond unit tests and have expansive test-plan coverage that covers all protocols.

This effort depends on [Testground Milestone 6](https://github.com/testground/testground/blob/master/ROADMAP.md#6-support-libp2ps-interoperability-testing-story-and-probelabs-work-as-a-way-to-drive-critical-testground-improvements)

<!-- TODO: List all major protocol test backlog items here.
Decide as a team which ones to prioritize and then assign to quarters.-->
#### 1. DHT server mode scale test
Test js-libp2p DHT Server Mode at scale (testbed of at least >20 nodes; ideally 100/1000+) in Testground
Depends on [C.1](#1-benchmarking-using-nix-builders)
Relates to [Testground Milestone 4 (for large scale tests.)](https://github.com/testground/testground/blob/master/ROADMAP.md#4-provide-a-testground-as-a-service-cluster-used-by-libp2p--ipfs-teams)
#### 2. AutoNat
Depends on [testground/NAT and/or firewall support](https://github.com/testground/testground/issues/1299)
#### 3. Hole Punching
Depends on [testground/NAT and/or firewall support](https://github.com/testground/testground/issues/1299)
#### 4. AutoRelay
#### 5. Custom topologies
#### 6. MTU Fixes
Depends on [testground/Network Simulation Fixes](https://github.com/testground/testground/issues/1492)
