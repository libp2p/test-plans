//go:build v0.20 || v0.21
// +build v0.20 v0.21

package compat

import (
	"context"
	"fmt"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/event"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/network"
	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/libp2p/go-libp2p/config"

	noise "github.com/libp2p/go-libp2p/p2p/security/noise"
	tls "github.com/libp2p/go-libp2p/p2p/security/tls"
)

type PeerAddrInfo = peer.AddrInfo

func NewLibp2(ctx context.Context, secureChannel string, opts ...config.Option) (host.Host, error) {
	security := getSecurityByName(secureChannel)

	return libp2p.New(
		append(opts, security)...,
	)
}

func getSecurityByName(secureChannel string) libp2p.Option {
	switch secureChannel {
	case "noise":
		return libp2p.Security(noise.ID, noise.New)
	case "tls":
		return libp2p.Security(tls.ID, tls.New)
	}
	panic(fmt.Sprintf("unknown secure channel: %s", secureChannel))
}

type ConnEventsSub struct {
	sub event.Subscription
}

func SubscribeToConnectedEvents(host host.Host) (ConnEventsSub, error) {
	sub, err := host.EventBus().Subscribe(new(event.EvtPeerConnectednessChanged))
	if err != nil {
		return ConnEventsSub{}, err
	}

	return ConnEventsSub{
		sub: sub,
	}, nil

}

func (s *ConnEventsSub) WaitForNConnectedEvents(n int) {
	connectedPeers := 0
	for e := range s.sub.Out() {
		if e.(event.EvtPeerConnectednessChanged).Connectedness == network.Connected {
			connectedPeers++
		}
		if connectedPeers == n {
			return
		}
	}
}
