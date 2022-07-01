//go:build v0.17 || v0.19
// +build v0.17 v0.19

package compat

import (
	"context"
	"fmt"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p/config"

	noise "github.com/libp2p/go-libp2p-noise"
	tls "github.com/libp2p/go-libp2p-tls"
)

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
