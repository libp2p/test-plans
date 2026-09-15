// AutoNAT v2 client for the test-plans interop suite. Runs as either the server
// (an AutoNAT v2 service that dials addresses back) or the client (asks the
// server to verify the reachability of its own address), orchestrated over redis.

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/muxer/yamux"
	"github.com/libp2p/go-libp2p/p2p/protocol/autonatv2"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	manet "github.com/multiformats/go-multiaddr/net"

	ma "github.com/multiformats/go-multiaddr"
	"github.com/redis/go-redis/v9"
)

// redisAddr is the fixed address of the orchestrating redis server.
const redisAddr = "redis:6379"

// serverAddrKey is the redis list the server pushes its dialable multiaddr to
// and the client pops it from.
const serverAddrKey = "AUTONAT_SERVER_ADDR"

// testTimeout bounds the whole run. The compose runner tears the stack down at
// 60s, so the client exits first with a status it can attribute.
const testTimeout = 55 * time.Second

// result is the single line the client prints on stdout on a completed
// reachability check.
type result struct {
	Reachable  bool   `json:"reachable"`
	TestedAddr string `json:"tested_addr"`
}

const (
	transportTCP  = "tcp"
	transportQUIC = "quic"

	modeServer = "server"
	modeClient = "client"
)

func main() {
	log.SetFlags(0)
	log.SetPrefix("autonat-client: ")

	if err := run(); err != nil {
		log.Fatalf("FAILED: %v", err)
	}
}

func run() error {
	transport := os.Getenv("TRANSPORT")
	switch transport {
	case transportTCP, transportQUIC:
	default:
		return fmt.Errorf("invalid TRANSPORT %q", transport)
	}
	mode := os.Getenv("MODE")
	switch mode {
	case modeServer, modeClient:
	default:
		return fmt.Errorf("invalid MODE %q", mode)
	}

	ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
	defer cancel()

	rdb := redis.NewClient(&redis.Options{Addr: redisAddr})
	defer rdb.Close()

	if err := waitForRedis(ctx, rdb); err != nil {
		return err
	}

	// The main host listens and serves; the dialer host performs AutoNAT
	// dial-backs from a separate host so each dial-back opens a new connection.
	h, err := newHost(transport, true)
	if err != nil {
		return fmt.Errorf("creating host: %w", err)
	}
	defer h.Close()

	dialer, err := newHost(transport, false)
	if err != nil {
		return fmt.Errorf("creating dialer host: %w", err)
	}
	defer dialer.Close()

	log.Printf("peer id: %s", h.ID())
	log.Printf("listening on: %v", h.Addrs())

	// AllowPrivateAddrs lets both the request and the dial-back use the private
	// addresses the peers hold on the flat test network.
	an, err := autonatv2.New(dialer, autonatv2.AllowPrivateAddrs)
	if err != nil {
		return fmt.Errorf("creating autonat: %w", err)
	}
	if err := an.Start(h); err != nil {
		return fmt.Errorf("starting autonat: %w", err)
	}
	defer an.Close()

	if mode == modeServer {
		return runServer(ctx, h, rdb)
	}
	return runClient(ctx, h, rdb, an)
}

// runServer publishes its dialable address and then serves AutoNAT requests
// until the compose runner stops the container.
func runServer(ctx context.Context, h host.Host, rdb *redis.Client) error {
	addr, err := dialableAddr(h)
	if err != nil {
		return err
	}

	if err := rdb.RPush(ctx, serverAddrKey, addr.String()).Err(); err != nil {
		return fmt.Errorf("publishing server address to %s: %w", serverAddrKey, err)
	}
	log.Printf("published server address to redis (key: %s): %s", serverAddrKey, addr)

	// The client exits first and the runner tears the stack down, so there is no
	// completion condition to wait on here.
	<-ctx.Done()
	return nil
}

// runClient connects to the server, asks it to verify the reachability of the
// client's own addresses and reports the verdict.
func runClient(ctx context.Context, h host.Host, rdb *redis.Client, an *autonatv2.AutoNAT) error {
	value, err := popValue(ctx, rdb, serverAddrKey, testTimeout)
	if err != nil {
		return fmt.Errorf("waiting for server address: %w", err)
	}
	serverAddr, err := ma.NewMultiaddr(value)
	if err != nil {
		return fmt.Errorf("parsing server multiaddr %q: %w", value, err)
	}

	serverInfo, err := peer.AddrInfoFromP2pAddr(serverAddr)
	if err != nil {
		return fmt.Errorf("extracting server peer info: %w", err)
	}

	if err := h.Connect(ctx, *serverInfo); err != nil {
		return fmt.Errorf("connecting to server: %w", err)
	}
	log.Printf("connected to server %s", serverInfo.ID)

	reqs := make([]autonatv2.Request, 0, len(h.Addrs()))
	for _, a := range h.Addrs() {
		if manet.IsIPLoopback(a) {
			continue
		}
		reqs = append(reqs, autonatv2.Request{Addr: a, SendDialData: true})
	}
	if len(reqs) == 0 {
		return errors.New("no candidate addresses to verify")
	}

	res, err := getReachability(ctx, an, reqs)
	if err != nil {
		return fmt.Errorf("reachability check: %w", err)
	}

	reachable := res.Reachability == network.ReachabilityPublic
	out := result{Reachable: reachable, TestedAddr: res.Addr.String()}
	b, err := json.Marshal(out)
	if err != nil {
		return fmt.Errorf("marshalling result: %w", err)
	}
	fmt.Println(string(b))

	if !reachable {
		return fmt.Errorf("address %s reported not reachable (%s)", res.Addr, res.Reachability)
	}
	return nil
}

// getReachability retries the reachability check while the client still has no
// AutoNAT server, which is the window before identify registers the server's
// protocol support.
func getReachability(ctx context.Context, an *autonatv2.AutoNAT, reqs []autonatv2.Request) (autonatv2.Result, error) {
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()

	for {
		res, err := an.GetReachability(ctx, reqs)
		if err == nil {
			return res, nil
		}
		if !errors.Is(err, autonatv2.ErrNoPeers) {
			return res, err
		}

		select {
		case <-ctx.Done():
			return autonatv2.Result{}, fmt.Errorf("waiting for an autonat server: %w", ctx.Err())
		case <-ticker.C:
		}
	}
}

// dialableAddr returns the host's first non-loopback listen address with its
// peer id encapsulated, which is what the client dials to reach the server.
func dialableAddr(h host.Host) (ma.Multiaddr, error) {
	p2pComponent, err := ma.NewMultiaddr("/p2p/" + h.ID().String())
	if err != nil {
		return nil, fmt.Errorf("building /p2p component: %w", err)
	}
	for _, a := range h.Addrs() {
		if manet.IsIPLoopback(a) {
			continue
		}
		return a.Encapsulate(p2pComponent), nil
	}
	return nil, errors.New("no non-loopback listen address")
}

// newHost builds a libp2p host for the given transport. When listen is false the
// host only dials, which is what the AutoNAT dial-back host needs.
func newHost(transport string, listen bool) (host.Host, error) {
	var opts []libp2p.Option

	switch transport {
	case transportTCP:
		opts = append(opts,
			libp2p.Transport(tcp.NewTCPTransport),
			libp2p.Security(noise.ID, noise.New),
			libp2p.Muxer(yamux.ID, yamux.DefaultTransport),
		)
		if listen {
			opts = append(opts, libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0"))
		}
	case transportQUIC:
		opts = append(opts, libp2p.Transport(libp2pquic.NewTransport))
		if listen {
			opts = append(opts, libp2p.ListenAddrStrings("/ip4/0.0.0.0/udp/0/quic-v1"))
		}
	default:
		return nil, fmt.Errorf("unsupported transport %q", transport)
	}

	if !listen {
		opts = append(opts, libp2p.NoListenAddrs)
	}

	return libp2p.New(opts...)
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

// popValue blocks on a redis list until an entry is available or the timeout
// passes.
func popValue(ctx context.Context, rdb *redis.Client, key string, timeout time.Duration) (string, error) {
	parts, err := rdb.BLPop(ctx, timeout, key).Result()
	if err != nil {
		return "", err
	}
	return parts[1], nil
}
