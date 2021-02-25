package main

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
	"github.com/testground/sdk-go/sync"
)

func simOpen(ctx context.Context, h host.Host, runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	// Configure Network & Wait till all peers finish configuring their network.
	client := initCtx.SyncClient
	netclient := initCtx.NetClient

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
		CallbackState: "network-configured",
		RoutingPolicy: network.AllowAll,
	}

	netclient.MustConfigureNetwork(ctx, config)
	client.MustSignalAndWait(ctx, "config-network", runenv.TestInstanceCount)

	// Publish our peerID AND address so other nodes know how to reach me.
	// Wait until all peers have exchanged addresses.
	pInfoTopic := sync.NewTopic("peers", &peer.AddrInfo{})
	pCh := make(chan *peer.AddrInfo)
	_, _ = client.MustPublishSubscribe(ctx, pInfoTopic, &peer.AddrInfo{
		ID:    h.ID(),
		Addrs: h.Addrs(),
	}, pCh)

	peers := make([]*peer.AddrInfo, 0, runenv.TestInstanceCount-1)
	for found := 1; found <= runenv.TestInstanceCount; found++ {
		p := <-pCh
		if h.ID() != p.ID {
			peers = append(peers, p)
		}
	}

	_, err := client.SignalAndWait(ctx, "collectAddrs", runenv.TestInstanceCount)
	if err != nil {
		return err
	}
	runenv.RecordMessage("exchanged addrs")

	// Connect all peers to each other and ensure we see the connection.
	for _, pi := range peers {
		err := h.Connect(ctx, *pi)
		if err != nil {
			err = fmt.Errorf("%s failed to connect to %s, err: %s", h.ID(), pi.ID, err)
			runenv.RecordFailure(err)
			return err
		}

		// ensure we saw one and ONLY one connection
		if len(h.Network().ConnsToPeer(pi.ID)) != 1 {
			err := fmt.Errorf("%s connected to %s, but saw %d connections", h.ID(), pi.ID, len(h.Network().ConnsToPeer(pi.ID)))
			runenv.RecordFailure(err)
			return err
		}
	}

	// Wait until all peers have finished dialing and ensure we still see one connection to each peer.
	_, err = client.SignalAndWait(ctx, "dial", runenv.TestInstanceCount)
	if err != nil {
		return err
	}

	// ensure again we have ONLY 1 connection between each peer
	for _, pi := range peers {
		if len(h.Network().ConnsToPeer(pi.ID)) != 1 {
			err := fmt.Errorf("final check: %s connected to %s, but saw %d connections", h.ID(), pi.ID, len(h.Network().ConnsToPeer(pi.ID)))
			runenv.RecordFailure(err)
			return err
		}
	}

	_, err = client.SignalAndWait(ctx, "final-check", runenv.TestInstanceCount)
	if err != nil {
		return err
	}

	if err := h.Close(); err != nil {
		return err
	}

	return nil
}
