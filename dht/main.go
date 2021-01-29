package main

import (
	test "github.com/libp2p/test-plans/dht/test"
	"github.com/testground/sdk-go/run"
)

var testCases = map[string]interface{}{
	"find-peers":        test.FindPeers,
	"find-providers":    test.FindProviders,
	"provide-stress":    test.ProvideStress,
	"store-get-value":   test.StoreGetValue,
	"get-closest-peers": test.GetClosestPeers,
	"bootstrap-network": test.BootstrapNetwork,
	"all":               test.All,
}

func main() {
	run.InvokeMap(testCases)
}
