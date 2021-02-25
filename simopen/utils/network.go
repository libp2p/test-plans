package utils

import (
	"context"
	"time"

	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
)

// ConfigureNetwork configures the network with some latency
func ConfigureNetwork(runenv *runtime.RunEnv, initCtx *run.InitContext) {
	config := &network.Config{
		// Control the "default" network. At the moment, this is the only network.
		Network: "default",

		// Enable this network. Setting this to false will disconnect this test
		// instance from this network. You probably don't want to do that.
		Enable: true,
		Default: network.LinkShape{
			Latency:   200 * time.Millisecond,
			Bandwidth: 1 << 20, // 1Mib
		},
		CallbackState:  "network-configured",
		RoutingPolicy:  network.AllowAll,
		CallbackTarget: runenv.TestInstanceCount,
	}

	initCtx.NetClient.MustConfigureNetwork(context.Background(), config)
}
