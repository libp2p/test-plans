package main

import (
	"github.com/testground/sdk-go/run"
)

var testcases = map[string]interface{}{
	"tcp-sim-open":  run.InitializedTestCaseFn(tcpSimOpen),
	"quic-sim-open": run.InitializedTestCaseFn(quicSimOpen),
}

func main() {
	run.InvokeMap(testcases)
}
