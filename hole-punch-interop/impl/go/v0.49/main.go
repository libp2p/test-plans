// Hole-punch client for the test-plans interop suite. Runs as either the dialer
// or the listener, orchestrated over redis.

package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/muxer/yamux"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/holepunch"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/redis/go-redis/v9"
)

// redisAddr is the fixed address of the orchestrating redis server.
const redisAddr = "redis:6379"

// listenClientPeerIDKey is the redis list the listener pushes its peer id to and
// the dialer pops it from.
const listenClientPeerIDKey = "LISTEN_CLIENT_PEER_ID"

// testTimeout bounds the whole run. The compose runner tears the stack down at
// 60s, so the client exits first with a status it can attribute.
const testTimeout = 55 * time.Second

// pingSize is the byte length of the payload echoed back over the hole-punched connection.
const pingSize = 32

// result is the single line the dialer prints on stdout on a successful hole punch.
type result struct {
	RttToHolePunchedPeerMillis int `json:"rtt_to_holepunched_peer_millis"`
}

func main() {
	log.SetFlags(0)
	log.SetPrefix("hole-punch-client: ")

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
	case modeListen, modeDial:
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

	relayMaddr, err := popRelayAddr(ctx, rdb, transport)
	if err != nil {
		return err
	}
	log.Printf("relay multiaddr: %s", relayMaddr)

	relayInfo, err := peer.AddrInfoFromP2pAddr(relayMaddr)
	if err != nil {
		return fmt.Errorf("extracting relay peer info: %w", err)
	}

	tracer := newHolePunchTracer()

	h, err := newHost(transport, tracer)
	if err != nil {
		return fmt.Errorf("creating host: %w", err)
	}
	defer h.Close()

	log.Printf("peer id: %s", h.ID())
	log.Printf("listening on: %v", h.Addrs())

	if err := connectToRelay(ctx, h, *relayInfo); err != nil {
		return err
	}

	if mode == modeDial {
		return runDialer(ctx, h, rdb, relayMaddr, tracer)
	}
	return runListener(ctx, h, rdb, *relayInfo)
}

// runListener reserves a slot on the relay, publishes its peer id and then serves
// until the compose runner stops the container.
func runListener(ctx context.Context, h host.Host, rdb *redis.Client, relayInfo peer.AddrInfo) error {
	if err := reserve(ctx, h, relayInfo); err != nil {
		return err
	}

	if err := waitForDCUtR(ctx, h); err != nil {
		return err
	}

	if err := rdb.RPush(ctx, listenClientPeerIDKey, h.ID().String()).Err(); err != nil {
		return fmt.Errorf("publishing peer id to %s: %w", listenClientPeerIDKey, err)
	}
	log.Printf("published peer id to redis (key: %s)", listenClientPeerIDKey)

	// The dialer exits first and the runner tears the stack down, so there is no
	// completion condition to wait on here.
	<-ctx.Done()
	return nil
}

// runDialer connects to the listener through the relay, waits for DCUtR to
// upgrade the connection to a direct one and reports the round-trip time.
func runDialer(ctx context.Context, h host.Host, rdb *redis.Client, relayMaddr ma.Multiaddr, tracer *holePunchTracer) error {
	listenerID, err := popValue(ctx, rdb, listenClientPeerIDKey, testTimeout)
	if err != nil {
		return fmt.Errorf("waiting for listener peer id: %w", err)
	}

	listenerPeerID, err := peer.Decode(listenerID)
	if err != nil {
		return fmt.Errorf("decoding listener peer id %q: %w", listenerID, err)
	}
	log.Printf("listener peer id: %s", listenerPeerID)

	circuitAddr := relayMaddr.Encapsulate(ma.StringCast("/p2p-circuit"))
	log.Printf("dialling listener through relay: %s", circuitAddr)

	// The dialer waits for its own hole punch service before opening the circuit,
	// since the listener starts the exchange as soon as the circuit opens.
	if err := waitForDCUtR(ctx, h); err != nil {
		return err
	}

	if err := h.Connect(ctx, peer.AddrInfo{
		ID:    listenerPeerID,
		Addrs: []ma.Multiaddr{circuitAddr},
	}); err != nil {
		return fmt.Errorf("connecting through relay: %w", err)
	}
	log.Printf("relayed connection established")

	if err := waitForDirectConn(ctx, h, listenerPeerID, tracer); err != nil {
		return err
	}
	log.Printf("direct connection established")

	rtt, err := pingDirect(ctx, h, listenerPeerID)
	if err != nil {
		return err
	}
	log.Printf("ping over direct connection: %s", rtt)

	b, err := json.Marshal(result{RttToHolePunchedPeerMillis: int(rtt.Milliseconds())})
	if err != nil {
		return fmt.Errorf("marshalling result: %w", err)
	}
	fmt.Println(string(b))
	return nil
}

// waitForDirectConn blocks until DCUtR reports success or a non-relayed
// connection to the peer appears.
//
// Both conditions are watched because go-libp2p only reports a hole punch
// through the tracer when the DCUtR exchange runs. If the holepuncher's initial
// direct dial happens to succeed, no hole punch is traced even though the
// connection is now direct, and the test should still pass.
func waitForDirectConn(ctx context.Context, h host.Host, pid peer.ID, tracer *holePunchTracer) error {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()

	for {
		if directConn(h, pid) != nil {
			return nil
		}

		select {
		case <-ctx.Done():
			return errors.New("timed out waiting for a direct connection")
		case err := <-tracer.failed:
			return fmt.Errorf("hole punch failed: %w", err)
		case <-tracer.succeeded:
			if directConn(h, pid) == nil {
				return errors.New("hole punch reported success but no direct connection exists")
			}
			return nil
		case <-ticker.C:
		}
	}
}

// directConn returns a connection to the peer that does not run over the relay.
func directConn(h host.Host, pid peer.ID) network.Conn {
	for _, conn := range h.Network().ConnsToPeer(pid) {
		if !isRelayed(conn) {
			return conn
		}
	}
	return nil
}

// isRelayed reports whether the connection runs over a relay circuit.
//
// The circuit component in the remote address is definitive, where the Limited
// flag is not: a relay can grant an unlimited circuit, whose connection reports
// Limited false while still running over the relay.
func isRelayed(conn network.Conn) bool {
	_, err := conn.RemoteMultiaddr().ValueForProtocol(ma.P_CIRCUIT)
	return err == nil
}

// pingDirect echoes a payload off the peer and returns the round-trip time.
//
// The ping service is not used because this has to fail rather than fall back
// when the connection is still relayed, and the returned stream is checked to
// confirm which connection carried it.
func pingDirect(ctx context.Context, h host.Host, pid peer.ID) (time.Duration, error) {
	s, err := h.NewStream(ctx, pid, ping.ID)
	if err != nil {
		return 0, fmt.Errorf("opening ping stream: %w", err)
	}
	defer s.Close()

	if isRelayed(s.Conn()) {
		return 0, errors.New("hole punch failed: ping stream is still relayed")
	}
	log.Printf("ping stream runs over %s", s.Conn().RemoteMultiaddr())

	sent := make([]byte, pingSize)
	if _, err := rand.Read(sent); err != nil {
		return 0, fmt.Errorf("generating ping payload: %w", err)
	}

	start := time.Now()
	if _, err := s.Write(sent); err != nil {
		return 0, fmt.Errorf("writing ping: %w", err)
	}

	received := make([]byte, pingSize)
	if _, err := io.ReadFull(s, received); err != nil {
		return 0, fmt.Errorf("reading ping response: %w", err)
	}
	rtt := time.Since(start)

	if !bytes.Equal(sent, received) {
		return 0, errors.New("ping response did not match the payload sent")
	}
	return rtt, nil
}

// waitForDCUtR blocks until the hole punch service has registered its stream
// handler, which it does at the same moment it starts watching for relayed
// connections.
//
// go-libp2p defers both until the host has observed a public address for itself,
// and the watcher only ever sees connections opened after it starts. A dialer
// arriving over the circuit before that point reaches a peer that never begins
// the exchange, so the listener holds its peer id back until the handler is in
// place.
func waitForDCUtR(ctx context.Context, h host.Host) error {
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()

	for {
		for _, p := range h.Mux().Protocols() {
			if p == holepunch.Protocol {
				log.Printf("hole punch service ready")
				return nil
			}
		}

		select {
		case <-ctx.Done():
			return errors.New("timed out waiting for the hole punch service to start")
		case <-ticker.C:
		}
	}
}

// reserve takes a relay slot so the dialer can reach this peer over a circuit.
func reserve(ctx context.Context, h host.Host, relayInfo peer.AddrInfo) error {
	reservation, err := client.Reserve(ctx, h, relayInfo)
	if err != nil {
		return fmt.Errorf("reserving a relay slot: %w", err)
	}

	log.Printf("relay reservation accepted, expires %s, vouched addrs %v",
		reservation.Expiration.Format(time.RFC3339), reservation.Addrs)
	return nil
}

func connectToRelay(ctx context.Context, h host.Host, relayInfo peer.AddrInfo) error {
	for attempt := 1; ; attempt++ {
		err := h.Connect(ctx, relayInfo)
		if err == nil {
			log.Printf("connected to relay %s", relayInfo.ID)
			return nil
		}
		log.Printf("connecting to relay (attempt %d): %v", attempt, err)

		// A first QUIC dial that loses its handshake packet puts the peer into
		// the swarm's dial backoff, where every later dial returns immediately
		// without trying. The backoff is cleared so each retry dials afresh.
		if sw, ok := h.Network().(*swarm.Swarm); ok {
			sw.Backoff().Clear(relayInfo.ID)
		}

		select {
		case <-ctx.Done():
			return fmt.Errorf("connecting to relay: %w", err)
		case <-time.After(500 * time.Millisecond):
		}
	}
}

func newHost(transport string, tracer *holePunchTracer) (host.Host, error) {
	opts := []libp2p.Option{
		libp2p.EnableHolePunching(holepunch.WithTracer(tracer)),
		libp2p.EnableRelay(),
		// Both peers sit behind a NAT the harness built for them, so reachability
		// is forced to private instead of being discovered.
		libp2p.ForceReachabilityPrivate(),
	}

	switch transport {
	case transportTCP:
		opts = append(opts,
			libp2p.Transport(tcp.NewTCPTransport),
			libp2p.Security(noise.ID, noise.New),
			libp2p.Muxer(yamux.ID, yamux.DefaultTransport),
			libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0"),
		)
	case transportQUIC:
		opts = append(opts,
			libp2p.Transport(libp2pquic.NewTransport),
			libp2p.ListenAddrStrings("/ip4/0.0.0.0/udp/0/quic-v1"),
		)
	default:
		return nil, fmt.Errorf("unsupported transport %q", transport)
	}

	return libp2p.New(opts...)
}

// holePunchTracer reports the outcome of the DCUtR exchange to the dialer.
type holePunchTracer struct {
	succeeded chan struct{}
	failed    chan error
}

func newHolePunchTracer() *holePunchTracer {
	return &holePunchTracer{
		succeeded: make(chan struct{}, 1),
		failed:    make(chan error, 1),
	}
}

func (t *holePunchTracer) Trace(evt *holepunch.Event) {
	log.Printf("holepunch %s: %+v", evt.Type, evt.Evt)

	e, ok := evt.Evt.(*holepunch.EndHolePunchEvt)
	if !ok {
		return
	}

	if e.Success {
		select {
		case t.succeeded <- struct{}{}:
		default:
		}
		return
	}

	select {
	case t.failed <- errors.New(e.Error):
	default:
	}
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

// popRelayAddr blocks on the relay address list for the transport and parses the
// entry the relay pushed.
func popRelayAddr(ctx context.Context, rdb *redis.Client, transport string) (ma.Multiaddr, error) {
	var key string
	switch transport {
	case transportTCP:
		key = "RELAY_TCP_ADDRESS"
	case transportQUIC:
		key = "RELAY_QUIC_ADDRESS"
	default:
		return nil, fmt.Errorf("unsupported transport %q", transport)
	}

	value, err := popValue(ctx, rdb, key, testTimeout)
	if err != nil {
		return nil, fmt.Errorf("waiting for relay address: %w", err)
	}
	maddr, err := ma.NewMultiaddr(value)
	if err != nil {
		return nil, fmt.Errorf("parsing relay multiaddr %q: %w", value, err)
	}
	return maddr, nil
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

const (
	transportTCP  = "tcp"
	transportQUIC = "quic"

	modeListen = "listen"
	modeDial   = "dial"
)
