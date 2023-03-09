package main

import (
	"bytes"
	"fmt"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"

	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	relay "github.com/libp2p/go-libp2p/p2p/protocol/circuitv1/relay"
	ma "github.com/multiformats/go-multiaddr"
)

func main() {
	makeRelayV1()
	select {}
}

func makeRelayV1() host.Host {
	// Stable key for testing. DO NOT USE IN PRODUCTION.
	zero := [32]byte{}
	zeroReader := bytes.NewReader(zero[:])
	priv, _, err := crypto.GenerateKeyPairWithReader(crypto.Ed25519, 32*8, zeroReader)
	if err != nil {
		panic(err)
	}

	opts := []libp2p.Option{
		libp2p.ListenAddrStrings(
			"/ip4/0.0.0.0/tcp/4003/ws",
		),
		libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport),
		libp2p.DefaultMuxers,
		libp2p.Identity(priv),
		libp2p.EnableRelay(),
	}

	host, err := libp2p.New(opts...)
	if err != nil {
		panic(err)
	}

	_, err = relay.NewRelay(host)
	if err != nil {
		panic(err)
	}

	// fmt.Println(host.Mux().Protocols())

	for _, addr := range host.Addrs() {
		a, err := ma.NewMultiaddr(fmt.Sprintf("/p2p/%s", host.ID().Pretty()))
		if err != nil {
			panic(err)
		}
		fmt.Println("p2p addr: ", addr.Encapsulate(a))
	}
	return host
}
