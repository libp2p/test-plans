//go:build v0.11
// +build v0.11

package compat

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/libp2p/go-libp2p/config"

	noise "github.com/libp2p/go-libp2p-noise"
	tls "github.com/libp2p/go-libp2p-tls"
)

type PeerAddrInfo = peer.AddrInfo

func NewLibp2(ctx context.Context, secureChannel string, opts ...config.Option) (host.Host, error) {
	security := getSecurityByName(secureChannel)

	return libp2p.New(
		ctx,
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
}

func SubscribeToConnectedEvents(host host.Host) (ConnEventsSub, error) {
	return ConnEventsSub{}, nil
}

func (s *ConnEventsSub) WaitForNConnectedEvents(n int) {
	// We can't subscribe to events here. Let's just do a timeout.
	time.Sleep(5 * time.Second)
}
