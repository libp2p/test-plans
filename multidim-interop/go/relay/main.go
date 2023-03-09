package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"

	// "github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/muxer/mplex"
	relay "github.com/libp2p/go-libp2p/p2p/protocol/circuitv1/relay"
	ma "github.com/multiformats/go-multiaddr"
)

func main() {
	var (
		redisAddr      = os.Getenv("redis_addr")
		testTimeoutStr = os.Getenv("test_timeout_seconds")
	)
	var testTimeout = 3 * time.Minute
	if testTimeoutStr != "" {
		secs, err := strconv.ParseInt(testTimeoutStr, 10, 32)
		if err == nil {
			testTimeout = time.Duration(secs) * time.Second
		}
	}
	if redisAddr == "" {
		redisAddr = "redis:6379"
	}

	ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
	defer cancel()

	// Get peer information via redis
	rClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: "",
		DB:       0,
	})
	defer rClient.Close()

	host := makeRelayV1()
	_, err := rClient.RPush(ctx, "relayAddr", host.Addrs()[0].Encapsulate(ma.StringCast("/p2p/"+host.ID().String())).String()).Result()
	if err != nil {
		panic(err)
	}
	select {}
}

func makeRelayV1() host.Host {
	r := rand.Reader
	// Generate a key pair for this host. We will use it at least
	// to obtain a valid host ID.
	priv, _, err := crypto.GenerateKeyPairWithReader(crypto.RSA, 2048, r)
	if err != nil {
		panic(err)
	}

	opts := []libp2p.Option{
		libp2p.DefaultTransports,
		libp2p.ListenAddrStrings(
			"/ip4/0.0.0.0/tcp/0/ws",
		),
		libp2p.Muxer("/mplex/6.7.0", mplex.DefaultTransport),
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
