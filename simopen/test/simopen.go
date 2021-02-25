package test

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/network"
	"github.com/libp2p/go-libp2p-core/peer"
	quic "github.com/libp2p/go-libp2p-quic-transport"
	"github.com/libp2p/go-tcp-transport"
	"github.com/libp2p/test-plans/simopen/utils"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
	ts "github.com/testground/sdk-go/sync"
	"golang.org/x/sync/errgroup"
)

// TcpSimOpen runs tests for the TCP Simultaneous Open functionality.
func TcpSimOpen(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	ip := initCtx.NetClient.MustGetDataNetworkIP()

	f := func(ctx context.Context) (context.Context, host.Host, error) {
		h, err := libp2p.New(ctx, libp2p.Transport(tcp.NewTCPTransport),
			libp2p.ListenAddrs(ma.StringCast(fmt.Sprintf("/ip4/%s/tcp/0", ip))))
		if err != nil {
			return nil, nil, err
		}
		return ctx, h, err
	}

	return simOpen(f, runenv, initCtx)
}

// QuicSimOpen runs tests for the QUIC Simultaneous Open scenario.
func QuicSimOpen(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	ip := initCtx.NetClient.MustGetDataNetworkIP()

	f := func(ctx context.Context) (context.Context, host.Host, error) {

		addr := ma.StringCast(fmt.Sprintf("/ip4/%s/udp/0/quic", ip))
		h, err := libp2p.New(ctx, libp2p.Transport(quic.NewTransport), libp2p.ListenAddrs(addr))
		if err != nil {
			return nil, nil, err
		}

		qCtx := network.WithSimultaneousConnect(ctx, "quic")
		return qCtx, h, err
	}

	return simOpen(f, runenv, initCtx)
}

func simOpen(hf func(ctx context.Context) (context.Context, host.Host, error), runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	iterations := runenv.IntParam("iterations")
	runenv.RecordMessage("starting test with %d iterations", iterations)
	utils.ConfigureNetwork(runenv, initCtx)
	client := initCtx.SyncClient

	// Lets go !
	for i := 0; i < iterations; i++ {
		c, cancel := context.WithTimeout(context.Background(), 600*time.Second)
		defer cancel()
		ctx, h, err := hf(c)
		if err != nil {
			return err
		}

		// Publish our peerID AND address so other nodes know how to reach me and synchronize.
		pInfoTopic := ts.NewTopic(string(mkState("peers", i)), &peer.AddrInfo{})
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
		client.MustSignalAndWait(ctx, mkState("collect-addrs", i), runenv.TestInstanceCount)

		// Connect all peers to each other, ensure we see the connection & synchronize.
		g, gctx := errgroup.WithContext(ctx)
		for _, px := range peers {
			pInfo := *px

			g.Go(func() error {
				err := h.Connect(gctx, pInfo)
				if err != nil {
					err = fmt.Errorf("%s failed to connect to %s, err: %s", h.ID(), pInfo.ID, err)
					runenv.RecordFailure(err)
					return err
				}

				// ensure we saw a connection
				if len(h.Network().ConnsToPeer(pInfo.ID)) == 0 {
					err = fmt.Errorf("%s connected to %s, but saw 0 connections", h.ID(), pInfo.ID)
					runenv.RecordFailure(err)
					return err
				}

				return nil
			})
		}
		if err := g.Wait(); err != nil {
			return err
		}
		client.MustSignalAndWait(ctx, mkState("dial", i), runenv.TestInstanceCount)

		// Shutdown Host and Synchronize for next iteration.
		if err := h.Close(); err != nil {
			return err
		}
		client.MustSignalAndWait(ctx, mkState("host-close", i), runenv.TestInstanceCount)
	}

	return nil
}

func mkState(str string, i int) ts.State {
	return ts.State(fmt.Sprintf("%s-%d", str, i))
}
