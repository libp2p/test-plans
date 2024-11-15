package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/event"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/identify"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	"github.com/multiformats/go-multiaddr"
)

const listenClientPeerID = "LISTEN_CLIENT_PEER_ID"
const redisAddr = "redis:6379"

type resultInfo struct {
	RttToHolePunchedPeerMillis int `json:"rtt_to_holepunched_peer_millis"`
}

func main() {
	tpt := os.Getenv("TRANSPORT")
	switch tpt {
	case "tcp", "quic":
	default:
		log.Fatal("invalid transport")
	}
	mode := os.Getenv("MODE")
	switch mode {
	case "listen", "dial":
	default:
		log.Fatal("invalid mode")
	}
	rClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: "",
		DB:       0,
	})
	defer rClient.Close()
	testTimeout := 3 * time.Minute
	ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
	defer cancel()
	waitForRedis(ctx, rClient)

	var err error
	var resultParts []string
	switch tpt {
	case "tcp":
		resultParts, err = rClient.BLPop(ctx, testTimeout, "RELAY_TCP_ADDRESS").Result()
	case "quic":
		resultParts, err = rClient.BLPop(ctx, testTimeout, "RELAY_QUIC_ADDRESS").Result()
	}
	if err != nil {
		log.Fatal("Failed to wait for listener to be ready")
	}
	relayAddr := multiaddr.StringCast(resultParts[1])

	ai, err := peer.AddrInfoFromP2pAddr(relayAddr)
	if err != nil {
		log.Fatal(err)
	}

	opts := []libp2p.Option{
		libp2p.EnableAutoRelayWithStaticRelays([]peer.AddrInfo{*ai}),
		libp2p.EnableHolePunching(),
	}
	switch tpt {
	case "tcp":
		opts = append(opts, libp2p.Transport(tcp.NewTCPTransport), libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0"))
	case "quic":
		opts = append(opts, libp2p.Transport(libp2pquic.NewTransport), libp2p.ListenAddrStrings("/ip4/0.0.0.0/udp/0/quic-v1"))
	}
	if mode == "listen" {
		opts = append(opts, libp2p.EnableAutoRelayWithStaticRelays([]peer.AddrInfo{*ai}))
	}

	identify.ActivationThresh = 1 // We only have one relay, so we should activate immediately
	h, err := libp2p.New(opts...)
	if err != nil {
		log.Fatal(err)
	}

	waitToConnectToRelay(ctx, h, *ai)

	switch mode {
	case "listen":
		// Listen on the relay
		e, err := h.EventBus().Emitter(new(event.EvtLocalReachabilityChanged))
		if err != nil {
			log.Fatal(err)
		}
		err = e.Emit(event.EvtLocalReachabilityChanged{Reachability: network.ReachabilityPrivate})
		if err != nil {
			log.Fatal(err)
		}

		timeoutTime := time.Now().Add(2 * time.Second)
		for time.Now().Before(timeoutTime) {
			log.Printf("Listening on %s", h.Addrs())
			if len(h.Addrs()) > 0 {
				break
			}

			time.Sleep(500 * time.Millisecond)
		}
		time.Sleep(time.Second) // ? sometimes the relay doesn't have the reservation yet?

		_, err = rClient.RPush(ctx, listenClientPeerID, h.ID().String()).Result()
		if err != nil {
			log.Fatal(err)
		}
		c := make(chan os.Signal, 1)
		signal.Notify(c, os.Interrupt)
		<-c
	case "dial":

		// Block on getting the relay's peer ID
		parts, err := rClient.BLPop(ctx, 30*time.Second, listenClientPeerID).Result()
		if err != nil {
			log.Fatal(err)
		}
		pid, err := peer.Decode(parts[1])
		if err != nil {
			log.Fatal(err)
		}
		circuitAddr := relayAddr.Encapsulate(multiaddr.StringCast("/p2p-circuit/"))
		err = h.Connect(ctx, peer.AddrInfo{
			ID:    pid,
			Addrs: []multiaddr.Multiaddr{circuitAddr},
		})
		if err != nil {
			log.Fatal(err)
		}

		log.Printf("Connected to relayed peer %s", pid)

		// Wait for a direct conn
		s, err := h.NewStream(ctx, pid, ping.ID)
		if err != nil {
			log.Fatal(err)
		}
		defer s.Close()
		// Send a ping message. Implementing this ourselves since the ping protocol allows for pings over relay.
		buf := [32]byte{}
		rand.Read(buf[:])
		start := time.Now()
		_, err = s.Write(buf[:])
		if err != nil {
			log.Fatal(err)
		}
		log.Printf("Is conn limited? %v. %s", s.Conn().Stat().Limited, s.Conn().RemoteMultiaddr())
		retBuf := [32]byte{}
		_, err = s.Read(retBuf[:])
		if err != nil {
			log.Fatal(err)
		}
		if !bytes.Equal(buf[:], retBuf[:]) {
			log.Fatal("Ping failed. Bytes did not match.")
		}
		result := resultInfo{
			RttToHolePunchedPeerMillis: int(time.Since(start).Milliseconds()),
		}
		b, err := json.Marshal(result)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(string(b))
	}

}

func waitForRedis(ctx context.Context, rClient *redis.Client) {
	for {
		if ctx.Err() != nil {
			log.Fatal("timeout waiting for redis")
		}

		// Wait for redis to be ready
		_, err := rClient.Ping(ctx).Result()
		if err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func waitToConnectToRelay(ctx context.Context, h host.Host, relayInfo peer.AddrInfo) {
	try := 0
	for {
		log.Printf("Attempting to connect to relay %s. Try #%d", relayInfo.ID, try)
		try++
		if ctx.Err() != nil {
			log.Fatal("timeout waiting for relay")
		}
		err := h.Connect(ctx, relayInfo)
		if err == nil {
			log.Printf("Connected to relay %s", relayInfo.ID)
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
}
