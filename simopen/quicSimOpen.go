package main

import (
	"context"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/network"
	quic "github.com/libp2p/go-libp2p-quic-transport"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
)

func quicSimOpen(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	ctx, cancel := context.WithTimeout(context.Background(), 600*time.Second)
	defer cancel()

	addr := ma.StringCast("/ip4/0.0.0.0/udp/0/quic")
	h, err := libp2p.New(ctx, libp2p.Transport(quic.NewTransport), libp2p.ListenAddrs(addr))
	if err != nil {
		return err
	}

	qCtx := network.WithSimultaneousConnect(ctx, "quic")
	return simOpen(qCtx, h, runenv, initCtx)
}
