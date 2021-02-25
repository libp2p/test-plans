package test

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/libp2p/go-tcp-transport"
	"github.com/libp2p/test-plans/simopen/utils"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
	ts "github.com/testground/sdk-go/sync"
	"golang.org/x/sync/errgroup"
)

// PeerGroupInfo struct is used to exchange information among peers about their libp2p ID, Address & Group name.
type PeerGroupInfo struct {
	ID      peer.ID
	Addrs   []ma.Multiaddr
	GroupId string
}

var (
	simOpenGroup    = "simopen"
	nonSimOpenGroup = "nonsimopen"
)

// SimOpenPeerToNonSimOpenPeerConnect tests dialing from a peer that supports the Simultaneous Open extension to a
// peer that does NOT support the Simultaneous Open extension.
func SimOpenPeerToNonSimOpenPeerConnect(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	utils.ConfigureNetwork(runenv, initCtx)
	return runBackwardCompatTest(simOpenGroup, runenv, initCtx)
}

// NonSimOpenPeerToSimOpenPeerConnect tests dialing from a peer that does NOT support the Simultaneous Open extension to a
// peer that supports the Simultaneous Open extension.
func NonSimOpenPeerToSimOpenPeerConnect(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	utils.ConfigureNetwork(runenv, initCtx)
	return runBackwardCompatTest(nonSimOpenGroup, runenv, initCtx)
}

func runBackwardCompatTest(dialerGroup string, runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	iterations := runenv.IntParam("iterations")
	runenv.RecordMessage("starting test with %d iterations", iterations)
	runenv.RecordMessage("dialer group is %s", dialerGroup)
	runenv.RecordMessage("my group is %s", runenv.TestGroupID)

	client := initCtx.SyncClient

	// calculate the number of dialer peers.
	var nDialers int
	if dialerGroup == runenv.TestGroupID {
		nDialers = runenv.TestGroupInstanceCount
	} else {
		nDialers = runenv.TestInstanceCount - runenv.TestGroupInstanceCount
	}
	nNonDialers := runenv.TestInstanceCount - nDialers
	ip := initCtx.NetClient.MustGetDataNetworkIP()

	runenv.RecordMessage("number of dialers: %d", nDialers)
	runenv.RecordMessage("number of non dialers: %d", nNonDialers)

	for i := 0; i < iterations; i++ {
		runenv.RecordMessage("running iteration-%d", i)
		ctx, cancel := context.WithTimeout(context.Background(), 600*time.Second)
		defer cancel()
		h, err := libp2p.New(ctx, libp2p.Transport(tcp.NewTCPTransport), libp2p.ListenAddrs(ma.StringCast(
			fmt.Sprintf("/ip4/%s/tcp/0", ip))))
		if err != nil {
			return err
		}
		runenv.RecordMessage("create host-%d", i)

		// If we are NOT in the dialer group, we should publish information about ourselves so dialer peers know how to dial us.
		pInfoTopic := ts.NewTopic(string(mkState("peers", i)), &PeerGroupInfo{})

		pCh := make(chan *PeerGroupInfo)
		seq, _ := client.MustPublishSubscribe(ctx, pInfoTopic, &PeerGroupInfo{
			ID:      h.ID(),
			Addrs:   h.Addrs(),
			GroupId: runenv.TestGroupID,
		}, pCh)
		runenv.RecordMessage("published %d", seq)

		if runenv.TestGroupID == dialerGroup {
			peers := make([]*PeerGroupInfo, 0, nNonDialers)
			for i := 1; i <= runenv.TestInstanceCount; i++ {
				runenv.RecordMessage("waiting for message")
				p := <-pCh
				runenv.RecordMessage("got peer %s", p.ID)
				if p.GroupId != runenv.TestGroupID {
					peers = append(peers, p)
				}
			}

			client.MustSignalAndWait(ctx, mkState("collect-addrs", i), nDialers)

			g, gctx := errgroup.WithContext(ctx)
			for _, px := range peers {
				pi := *px
				g.Go(func() error {
					err := h.Connect(gctx, peer.AddrInfo{
						ID:    pi.ID,
						Addrs: pi.Addrs,
					})
					if err != nil {
						err = fmt.Errorf("%s failed to connect to %s, err: %s", h.ID(), pi.ID, err)
						return err
					}

					// ensure we saw a connection.
					if len(h.Network().ConnsToPeer(pi.ID)) == 0 {
						err = fmt.Errorf("%s connected to %s, but saw 0 connections", h.ID(), pi.ID)
						return err
					}

					return nil
				})
			}
			if err := g.Wait(); err != nil {
				runenv.RecordFailure(err)
				return err
			}
		}

		client.MustSignalAndWait(ctx, mkState("done", i), runenv.TestInstanceCount)
		runenv.RecordMessage("finished dialing-%d", i)

		// Shutdown Hosts & synchronize
		if err := h.Close(); err != nil {
			return err
		}
		client.MustSignalAndWait(ctx, mkState("host-close", i), runenv.TestInstanceCount)
		runenv.RecordMessage("closed host- %d", i)
	}

	return nil
}
