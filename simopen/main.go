package main

import (
	"github.com/libp2p/test-plans/simopen/test"
	"github.com/testground/sdk-go/run"
)

var testcases = map[string]interface{}{
	"tcp-sim-open":  run.InitializedTestCaseFn(test.TcpSimOpen),
	"quic-sim-open": run.InitializedTestCaseFn(test.QuicSimOpen),

	// only for tcp
	"sim-nonsim-dial": run.InitializedTestCaseFn(test.SimOpenPeerToNonSimOpenPeerConnect),

	// only for tcp
	"nonsim-sim-dial": run.InitializedTestCaseFn(test.NonSimOpenPeerToSimOpenPeerConnect),
}

func main() {
	run.InvokeMap(testcases)
}
