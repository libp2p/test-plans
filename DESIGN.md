# libp2p testing story

- Status: Draft

---

## Overview

This document describes our process for testing interoperability & backward compatibility in libp2p.

**Why care about this:**

- Interoperability is a shared problem
    - we don’t have a single blessed reference implementation that we use for conformance testing.
    - No single maintainer (whether libp2p or ipdx) will succeed without everyone's involvement.
- We want to share a Testing Story with the world that shows we care about quality & interop.
- We want to encourage other implementations to join the testing party.

**Context:**

- We completed a “PING” interop test with Testground. It is running in go and rust-libp2p CIs.
- It means we “proved” that we can write and run interop tests between versions AND implementation.

# Libp2p Testing Matrix

*What do we want to test next?*

|                                   | go-libp2p | rust-libp2p | js-libp2p (node) | js-libp2p (browser) | jvm-libp2p | nim-libp2p |
| ---                               | ---       | ---         | ---              | ---                 | ---        | ---        |
| Simple PING [#35][issue-35]       | ✅ | ✅ | 🍎 | 🔥 |  |  |
| Circuit Relay                     |  |  |  |  |  |  |
| WebTransport Transport            | 🔥 | 🔥 | 🔥 | 🔥 |  |  |
| WebRTC Transport                  | 🔥 | 🔥 | 🔥 | 🔥 |  |  |
| NAT Traversal                     |  |  |  |  |  |  |
| Hole Punching (STUN)              |  |  |  |  |  |  |
| Identify Protocol                 |  |  |  |  |  |  |
| AutoNAT                           |  |  |  |  |  |  |
| DHT                               |  |  |  |  |  |  |
| QUIC                              |  |  |  |  |  |  |
| Benchmarking?                     |  |  |  |  |  |  |

**Dependencies**

- Anything `js-libp2p` related requires the `ping` test to start
- Benchmarking must relate to [Remote Runners][remote-runners]

**Questions**

- When do we revisit this table to discuss priorities and add new tests?

**Legend**

- ✅ Done
- 🚚 In Progress
- 🔥 Highest Priority
- 🍎 Low-hanging fruit
- 🧊 Lowest priority

# How do we test libp2p interop at ProtocolLabs?

*(this is pretty much what happen with the go|rust-libp2p ping tests)*

I (laurent) haven’t had time to look at [libp2p/interop](https://github.com/libp2p/interop/actions/runs/3021456724) yet. Some information may be missing.

<aside>
1️⃣ *Before working on a new feature, the libp2p maintainers come together and agree on a description of the new test plan.*

</aside>

**Example:**

- [IPFS Test Story in libp2p/interop](https://github.com/libp2p/interop/blob/master/pdd/PDD-THE-IPFS-BUNDLE.md)

**Question:**

- What should be the format for this description?
- Can we live with a rough “here is a general idea of what the test should do”, and let the first implementor figure out the details?
- Do we need to make these decisions now? (09-09-2022)

<aside>
2️⃣ *The maintainers agree on which implementation will provide the reference test implementation (go, rust, js, or other). This implementation is written for Testground and merged in the `libp2p/test-plan` repository.*

</aside>

**Example:**

- https://github.com/libp2p/test-plans/pull/9 “add an instructional libp2p ping test plan”

**Why:**

- During implementation, some decisions might be taken on how coordination works, details of the tests, etc. It will be easier to clear the path from one implementation.

<aside>
3️⃣ Once this implementation is merged, the reference implementation enables the test in their CI. It will be a “simple” test that runs the current branch against the last N implementations.

</aside>

**Example:**

- https://github.com/libp2p/go-libp2p/pull/1625 “ci: run testground:ping plan on pull requests” in go-libp2p

<aside>
4️⃣ Other implementation will provide their version of the test. And enable a similar test in CI

</aside>

**Example:**

- https://github.com/libp2p/test-plans/pull/26 “ping/rust: introduce rust cross-version test”
- https://github.com/libp2p/rust-libp2p/pull/2835 “.github: introduce interop tests” in rust-libp2p

<aside>
5️⃣ Once multiple implementations have been provided and are running the test in CI, each project will add a “big” test workflow in their Release Process.
This “big test” runs the test between every known implementation & version.
It might be enabled in a nightly job too.

</aside>

**Example:**

- TODO: add the `full` interop test to `go-libp2p` + update their release documentation.

## Questions

- When do we revisit this scenario to improve and gather feedback?
    - How do we evaluate progress & success?
        - When we’re able to use these tests for benchmarking probably.
    - What’s the plan for the day when everything starts to break?
    - What’s the plan for the time when we start to crumble under test complexity?
- Maintenance
    - Tests will need updates on new releases, etc.
- What are the dependencies between tests?
    - ex: Does it make sense to test HOLE PUNCHING if you don’t test AUTONAT first?

## Refs

detrimental

- [https://docs.libp2p.io/concepts/protocols/](https://docs.libp2p.io/concepts/protocols/)
- libp2p interop in [Interop Repository](https://github.com/libp2p/interop)
- [libp2p interop issue](https://github.com/libp2p/interop/issues/70)
- [libp2p/interop test plans](https://github.com/libp2p/interop/blob/master/pdd/PDD-THE-IPFS-BUNDLE.md)


[issue-35]: https://github.com/libp2p/test-plans/issues/35
[remote-runners]: https://pl-strflt.notion.site/Remote-Runners-c4ad4886c4294fb6a6f8afd9c0c5b73c