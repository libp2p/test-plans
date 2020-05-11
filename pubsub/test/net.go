package main

import (
	"context"
	"math/rand"
	"time"

	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/runtime"
)

// setupNetwork instructs the sidecar (if enabled) to setup the network for this
// test case.
func setupNetwork(ctx context.Context, runenv *runtime.RunEnv, netParams NetworkParams, netclient *network.Client) error {
	if !runenv.TestSidecar {
		return nil
	}

	// Wait for the network to be initialized.
	runenv.RecordMessage("Waiting for network initialization")
	err := netclient.WaitNetworkInitialized(ctx)
	if err != nil {
		return err
	}
	runenv.RecordMessage("Network init complete")

	latency := netParams.latency
	if netParams.latencyMax > 0 {
		// If a maximum latency is supplied, choose a random latency between
		// latency and max latency
		latency += time.Duration(rand.Float64() * float64(netParams.latencyMax-latency))
	}

	config := &network.Config{
		Network: "default",
		Enable:  true,
		Default: network.LinkShape{
			Latency:   latency,
			Bandwidth: uint64(netParams.bandwidthMB) * 1024 * 1024,
			Jitter:    (time.Duration(netParams.jitterPct) * netParams.latency) / 100,
		},
		CallbackState: "network-configured",
	}

	// random delay to avoid overloading weave (we hope)
	delay := time.Duration(rand.Intn(1000)) * time.Millisecond
	<-time.After(delay)
	err = netclient.ConfigureNetwork(ctx, config)
	if err != nil {
		return err
	}

	runenv.RecordMessage("egress: %s latency (%d%% jitter) and %dMB bandwidth", netParams.latency, netParams.jitterPct, netParams.bandwidthMB)
	return nil
}
