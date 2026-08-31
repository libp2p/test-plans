// Relay server for the test-plans hole-punch interop suite. Listens on TCP and
// QUIC at once and publishes each listen address to redis for the clients.

package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/p2p/muxer/yamux"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	ma "github.com/multiformats/go-multiaddr"
	manet "github.com/multiformats/go-multiaddr/net"
	"github.com/redis/go-redis/v9"
)

// redisAddr is the fixed address of the orchestrating redis server.
const redisAddr = "redis:6379"

const (
	// relayTCPAddressKey is the redis list the TCP listen address is pushed to.
	relayTCPAddressKey = "RELAY_TCP_ADDRESS"
	// relayQUICAddressKey is the redis list the QUIC listen address is pushed to.
	relayQUICAddressKey = "RELAY_QUIC_ADDRESS"
)

// clientCount is the number of clients that pop each relay address from redis.
const clientCount = 2

// startupTimeout bounds the time to reach the point where the relay is serving.
// After that the relay runs until the compose runner stops it.
const startupTimeout = 60 * time.Second

func main() {
	log.SetFlags(0)
	log.SetPrefix("relay: ")

	if err := run(); err != nil {
		log.Fatalf("FAILED: %v", err)
	}
}

func run() error {
	ctx, cancel := context.WithTimeout(context.Background(), startupTimeout)
	defer cancel()

	rdb := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer rdb.Close()

	if err := waitForRedis(ctx, rdb); err != nil {
		return err
	}

	h, err := newHost()
	if err != nil {
		return fmt.Errorf("creating host: %w", err)
	}
	defer h.Close()

	log.Printf("peer id: %s", h.ID())

	tcpAddr, quicAddr, err := listenAddrs(ctx, h)
	if err != nil {
		return err
	}

	if err := publish(ctx, rdb, relayTCPAddressKey, withPeerID(tcpAddr, h)); err != nil {
		return err
	}
	if err := publish(ctx, rdb, relayQUICAddressKey, withPeerID(quicAddr, h)); err != nil {
		return err
	}

	log.Printf("relay ready, waiting for connections")

	// The dialer's exit tears the stack down, so the relay serves until the
	// runner signals it.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	return nil
}

func newHost() (host.Host, error) {
	return libp2p.New(
		libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0", "/ip4/0.0.0.0/udp/0/quic-v1"),
		libp2p.Transport(tcp.NewTCPTransport),
		libp2p.Transport(libp2pquic.NewTransport),
		libp2p.Security(noise.ID, noise.New),
		libp2p.Muxer(yamux.ID, yamux.DefaultTransport),
		libp2p.EnableRelayService(),
		// The relay sits on the WAN side of both NATs on a routable address the
		// harness assigned, which it advertises so reservations carry an address.
		libp2p.ForceReachabilityPublic(),
	)
}

// listenAddrs waits for the host to bind and returns its reachable TCP and QUIC
// addresses.
func listenAddrs(ctx context.Context, h host.Host) (tcpAddr, quicAddr ma.Multiaddr, err error) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		tcpAddr, quicAddr = classifyAddrs(h.Addrs())
		if tcpAddr != nil && quicAddr != nil {
			log.Printf("listening on: %s and %s", tcpAddr, quicAddr)
			return tcpAddr, quicAddr, nil
		}

		select {
		case <-ctx.Done():
			return nil, nil, fmt.Errorf("timed out waiting for listen addresses, have %v", h.Addrs())
		case <-ticker.C:
		}
	}
}

// classifyAddrs picks the reachable TCP and QUIC addresses from the host's set,
// preferring public ones so a stray docker address is not advertised.
func classifyAddrs(addrs []ma.Multiaddr) (tcpAddr, quicAddr ma.Multiaddr) {
	for _, addr := range addrs {
		if manet.IsIPLoopback(addr) {
			continue
		}
		if _, err := addr.ValueForProtocol(ma.P_QUIC_V1); err == nil {
			quicAddr = preferPublic(quicAddr, addr)
			continue
		}
		if _, err := addr.ValueForProtocol(ma.P_TCP); err == nil {
			tcpAddr = preferPublic(tcpAddr, addr)
		}
	}
	return tcpAddr, quicAddr
}

// preferPublic keeps the current address unless the candidate is public and the
// current one is not.
func preferPublic(current, candidate ma.Multiaddr) ma.Multiaddr {
	if current == nil {
		return candidate
	}
	if !manet.IsPublicAddr(current) && manet.IsPublicAddr(candidate) {
		return candidate
	}
	return current
}

func withPeerID(addr ma.Multiaddr, h host.Host) string {
	return fmt.Sprintf("%s/p2p/%s", addr, h.ID())
}

// publish pushes the address onto its redis list once per client that pops it.
func publish(ctx context.Context, rdb *redis.Client, key, addr string) error {
	for i := 0; i < clientCount; i++ {
		if err := rdb.RPush(ctx, key, addr).Err(); err != nil {
			return fmt.Errorf("publishing %s to redis: %w", key, err)
		}
	}
	log.Printf("published %s to redis (key: %s, x%d)", addr, key, clientCount)
	return nil
}

func waitForRedis(ctx context.Context, rdb *redis.Client) error {
	for {
		if err := rdb.Ping(ctx).Err(); err == nil {
			return nil
		}

		select {
		case <-ctx.Done():
			return errors.New("timed out waiting for redis")
		case <-time.After(100 * time.Millisecond):
		}
	}
}
