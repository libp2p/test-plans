# Short Term
(getting ready for lab days)

## Outcome:

- The repository covers:
    - (rust, go, nodejs, browserjs) x (ping test)
- We have a working demonstration and a presentation for the event
- We have a single Dashboard to track the current state of interop testing


## EPICs

- There is a clear way to tell the state of libp2p's interoperability testing
    - Create a page that tells me which implementations are supported by our interop infrastructure,
    - This page signal the status of each test  (not implemented / implemented / broken / passing)
    - This page is generated automatically, nightly
- The `lip2p/interop` test suite covers essential features for the demonstration
    - browserjs
    - nodejs
    - webtransport
    - webrtc
- The full `libp2p/interop` test suite is used before releasing any new versions
    - Go + Rust + JS libp2p release processes contain a call to this workflow
    - Maintainers might enable this workflow for nightly runs
- The light `libp2p/interop` test suite is used with every new Pull Request
    - This makes sure we keep the test green 
- We fixed every known stability issue with the `libp2p/interop` test suite
    - [Issue 36](https://github.com/libp2p/test-plans/issues/36)


# Medium Term

## EPICs

- `libp2p/test-plans` maintainers have a straightforward way to track the test suite stability and performances
    - We can track the status of every test combination stability from the interop project itself
    - We can easily measure the consequence (improvements) of a pull request to the libp2p/interop repository
    - We are alerted when an interop test starts failing on one of our client repositories, and we can dispatch the alert to repo maintainers,
- We have an explicit, working, Design Process for adding new tests
    - The design is documented in `./ROADMAP.md`,
    - The design is followed by the team when we add new features,
    - There is a clear path when it comes to testing new features. This might mean testing multiple `masters` against each other.

# Long Term

## EPICs

- The Libp2p Team is using remote runners for benchmarking
- Libp2p interop covers essential features and implementations
    - NAT Traversal / Hole Punching
    - Custom Topologies
    - MTU Fixes
- Libp2p interop is used to test new features
    - The design process is clear and well defined
- `libp2p/interop` and `libp2p/test-plans` are working together
    - They are either merged or somehow know about each other.
- We have a more stable build process that doesn't risk breaking
    - We generate artifacts for old versions during merges to the libp2p repositories https://github.com/libp2p/test-plans/issues/35#issuecomment-1254991985