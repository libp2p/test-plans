package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/go-redis/redis/v8"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/crypto"
	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	"github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	ma "github.com/multiformats/go-multiaddr"
)

func main() {
	transport := os.Getenv("TRANSPORT")
	mode := os.Getenv("MODE")

	// Connect to Redis for peer information
	rClient := redis.NewClient(&redis.Options{
		Addr: "redis:6379",
	})
	defer rClient.Close()

	ctx := context.Background()
	var relayAddr ma.Multiaddr;
	var err error;

	if transport == "tcp" {
		relayAddr, err = ma.NewMultiaddr(rClient.Get(ctx, "RELAY_TCP_ADDRESS").Val())
		if err != nil {
            log.Fatal(err)
        }
	} else if transport == "quic" {
		relayAddr, err = ma.NewMultiaddr(rClient.Get(ctx, "RELAY_QUIC_ADDRESS").Val())
		if err != nil {
            log.Fatal(err)
        }
	} else {
		log.Fatal("Unknown transport protocol")
	}

	// Generate identity for the client
	priv, _, err := crypto.GenerateEd25519Key(nil)
	if err != nil {
		log.Fatal(err)
	}

	// Initialize the client
	h, err := libp2p.New(
		libp2p.Identity(priv),
		libp2p.Transport(tcp.NewTCPTransport, libp2pquic.NewTransport),
		libp2p.Transport(libp2pquic.NewTransport),
		libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic"),
		libp2p.ForceReachabilityPrivate(),
		libp2p.EnableHolePunching(),
	)
	if err != nil {
		log.Fatal(err)
    }
	// Initialize the PingService
    pingService := ping.NewPingService(h)

    relayInfo, err := peer.AddrInfoFromP2pAddr(relayAddr)
    if err != nil {
        log.Fatal(err)
    }
    err = h.Connect(ctx, *relayInfo)
    if err != nil {
        log.Fatal("Failed to connect to relay:", err)
    }

	if mode == "listen" {
		_, err = client.Reserve(context.Background(), h, *relayInfo)
    	if err != nil {
    		log.Printf("unreachable2 failed to receive a relay reservation from relay1. %v", err)
    	}

		// Set the peer ID in Redis
        err = rClient.Set(ctx, "LISTEN_CLIENT_PEER_ID", h.ID().Pretty(), 0).Err()
        if err != nil {
            log.Fatalf("Failed to set peer ID in Redis: %v", err)
        }
	} else if mode == "dial" {
		// Dial mode: Fetch the peer ID from Redis and try to establish a hole-punched connection
		listeningPeerIDStr := rClient.Get(ctx, "LISTEN_CLIENT_PEER_ID").Val()
		listeningPeerID, err := peer.Decode(listeningPeerIDStr)
		if err != nil {
			log.Fatal(err)
		}

        listeningPeerAddr := relayAddr.Encapsulate(ma.StringCast("/p2p-circuit")).Encapsulate(ma.StringCast("/p2p/" + listeningPeerIDStr))

        listeningPeerAddrInfo, err := peer.AddrInfoFromP2pAddr(listeningPeerAddr)
        if err != nil {
            log.Fatal(err)
        }

		err = h.Connect(ctx, *listeningPeerAddrInfo)
		if err != nil {
			log.Fatal("Failed to connect to peer via relay:", err)
		}

		// Measure RTT using ping
        rttCh := pingService.Ping(ctx, listeningPeerID)
        rtt, ok := <-rttCh
        if ok {
            fmt.Println("RTT:", rtt.RTT)
            return;
        } else {
            log.Println("Failed to measure RTT or ping service terminated.")
        }

	} else {
		log.Fatal("Unknown mode")
	}

	// Hang so the program doesn't exit
	<-make(chan struct{})
}

func extractPeerIDFromMultiaddr(addrStr string) (peer.ID, error) {
	addr, err := ma.NewMultiaddr(addrStr)
	if err != nil {
		return "", err
	}

	info, err := peer.AddrInfoFromP2pAddr(addr)
	if err != nil {
		return "", err
	}

	return info.ID, nil
}
