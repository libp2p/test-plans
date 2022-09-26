# Short Term
(getting ready for lab days)

## Outcome:

- The repository covers:
	- (rust, go, nodejs, browserjs) x (ping test)
- We have a working demonstration + presentation for the event
- We have a single Dashboard to track the current state of interop testing


## EPICs

- There is a clear way to tell the state of libp2p's interoperability testing
	- Create a page that tells me which implementations are supported by our interop infrastructure
	- This page tells us combination of test is not implemented / implemented / broken / passing
	- (LATER) This page is generated automatically
- The `lip2p/interop` test suite covers essential features for the demonstration
	- browserjs
	- nodejs
	- webtransport
	- webrtc
- The full `libp2p/interop` test suite is used before releasing any new versions
	- Go + Rust + JS libp2p release processes contains a call to this workflow
	- This workflow might be enabled for nightly runs
- The light `libp2p/interop` testsuite is used with every new Pull Request
	- This make sure we keep the test green 
- We fixed every known stability issues with the `libp2p/interop` testsuite
	- TODO: list here


# Medium Term

## EPICs

- We have a clear way to track the testsuite stability and performances
	- We can track the status of every test combination stability from the interop project itself
	- We can easily measure the consequence (improvements) of a pull request to the libp2p/interop repository
	- We are alerted when an interop test starts failing on one of our client repository and we can dispatch the alert to a repo maintainers or fix it ourselves.
- We have an explicit, working, Design Process for adding new tests
	- The design is documented in
	- The design is used by the team when we add new features
	- There are clear path when it comes to testing new features. This might mean testing multiple `master` against each other.
- We have a more stable build process that don't risk breaking 
	- We generate artifacts for old versions during merges to the libp2p repositories https://github.com/libp2p/test-plans/issues/35#issuecomment-1254991985


# Long Term

## EPICs

- Libp2p interop covers essential features and implementations
	- NAT Traversal
- Libp2p interop is used to test new features
	- The design process is clear and well defined
- Libp2p interop and libp2p test-plans are working together
	- Either merged as one
	- or "sync'd"
