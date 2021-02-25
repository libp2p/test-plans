package main

import (
	"context"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
)

func tcpSimOpen(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	ctx, cancel := context.WithTimeout(context.Background(), 600*time.Second)
	defer cancel()
	// default transport is TCP
	h, err := libp2p.New(ctx)
	if err != nil {
		return err
	}

	return simOpen(ctx, h, runenv, initCtx)
}
