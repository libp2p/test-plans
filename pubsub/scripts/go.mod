// This module only exists so that our script can invoke tracestat using `go run` instead of having to
// install the tracestat binary.

module github.com/libp2p/test-plans/pubsub/scripts

go 1.14

require github.com/libp2p/go-libp2p-pubsub-tracer v0.0.0-20200120141315-151ce254cf29 // indirect
