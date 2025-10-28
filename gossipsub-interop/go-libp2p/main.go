package main

import (
	"context"
	"crypto/ed25519"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"log/slog"
	"net"
	"os"
	"strings"
	"sync/atomic"
	"time"

	"github.com/libp2p/go-libp2p"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
	pubsubpb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	"github.com/quic-go/quic-go"
	"go.uber.org/fx"
)

var (
	paramsFileFlag = flag.String("params", "", "the path to the params file")
)

// pubsubOptions creates a list of options to configure our router with.
func pubsubOptions(slogger *slog.Logger, params pubsub.GossipSubParams) []pubsub.Option {
	tr := gossipTracer{logger: slogger.With("service", "gossipsub")}
	psOpts := []pubsub.Option{
		pubsub.WithMessageSignaturePolicy(pubsub.StrictNoSign),
		pubsub.WithNoAuthor(),
		pubsub.WithMessageIdFn(func(pmsg *pubsubpb.Message) string {
			return CalcID(pmsg.Data)
		}),
		// TODO: probably make these experiment parameters
		pubsub.WithPeerOutboundQueueSize(600),
		pubsub.WithValidateQueueSize(600),
		pubsub.WithMaxMessageSize(10 * 1 << 20),
		pubsub.WithGossipSubParams(params),
		pubsub.WithEventTracer(&tr),
		// TODO: Allow adjusting/disabling this value with a script instruction
		// or through the gossipsub params
		pubsub.WithNFastestPeers(4),
	}

	return psOpts
}

// compute a private key for node id
func nodePrivKey(id int) crypto.PrivKey {
	seed := make([]byte, ed25519.SeedSize)
	binary.LittleEndian.PutUint64(seed[:8], uint64(id))
	data := ed25519.NewKeyFromSeed(seed)

	privkey, err := crypto.UnmarshalEd25519PrivateKey(data)
	if err != nil {
		panic(err)
	}
	return privkey
}

type ExperimentParams struct {
	Script ScriptInstructions `json:"script"`
}

func readParams(path string) (ExperimentParams, error) {
	if path == "" {
		return ExperimentParams{}, fmt.Errorf("params file must be set")
	}
	if !strings.HasSuffix(path, ".json") {
		return ExperimentParams{}, fmt.Errorf("params file must be a .json file")
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return ExperimentParams{}, fmt.Errorf("params file does not exist")
	}
	f, err := os.Open(path)
	if err != nil {
		return ExperimentParams{}, fmt.Errorf("failed to open params file: %w", err)
	}
	defer f.Close()

	var params ExperimentParams
	if err := json.NewDecoder(f).Decode(&params); err != nil {
		return ExperimentParams{}, fmt.Errorf("failed to decode params file: %w", err)
	}
	return params, nil
}

func main() {
	startTime := time.Now()

	flag.Parse()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	params, err := readParams(*paramsFileFlag)
	if err != nil {
		panic(err)
	}

	hostname, err := os.Hostname()
	if err != nil {
		panic(err)
	}

	// parse for the node id
	var nodeId int
	if _, err := fmt.Sscanf(hostname, "node%d", &nodeId); err != nil {
		panic(err)
	}

	// listen for incoming connections
	h, err := libp2p.New(
		// libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/9000"),
		libp2p.ListenAddrStrings("/ip4/0.0.0.0/udp/9000/quic-v1"),
		libp2p.Identity(nodePrivKey(nodeId)),
		QUICOnShadow(),
	)
	if err != nil {
		panic(err)
	}

	logger := log.New(os.Stderr, "", log.LstdFlags|log.Lmicroseconds)
	slogger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	connector := &ShadowConnector{}
	err = RunExperiment(ctx, startTime, logger, slogger, h, nodeId, connector, params)
	if err != nil {
		panic(err)
	}
}

type ShadowConnector struct{}

func (c *ShadowConnector) ConnectTo(ctx context.Context, h host.Host, id int) error {
	// resolve for ip addresses of the discovered node
	addrs, err := net.LookupHost(fmt.Sprintf("node%d", id))
	if err != nil || len(addrs) == 0 {
		return fmt.Errorf("failed resolving for the address of node%d: %v", id, err)
	}

	// craft an addr info to be used to connect
	peerId, err := peer.IDFromPrivateKey(nodePrivKey(id))
	if err != nil {
		panic(err)
	}
	// addr := fmt.Sprintf("/ip4/%s/tcp/9000/p2p/%s", addrs[0], peerId)
	addr := fmt.Sprintf("/ip4/%s/udp/9000/quic-v1/p2p/%s", addrs[0], peerId)
	info, err := peer.AddrInfoFromString(addr)
	if err != nil {
		panic(err)
	}

	// connect to the peer
	if err = h.Connect(ctx, *info); err != nil {
		return fmt.Errorf("failed connecting to node%d: %v", id, err)
	}
	return nil
}

type MockSourceIPSelector struct {
	ip atomic.Pointer[net.IP]
}

func (m *MockSourceIPSelector) PreferredSourceIPForDestination(_ *net.UDPAddr) (net.IP, error) {
	return *m.ip.Load(), nil
}

func QUICOnShadow() libp2p.Option {
	m := &MockSourceIPSelector{}
	quicReuseOpts := []quicreuse.Option{
		quicreuse.OverrideSourceIPSelector(func() (quicreuse.SourceIPSelector, error) {
			return m, nil
		}),
		quicreuse.OverrideListenUDP(func(l string, address *net.UDPAddr) (net.PacketConn, error) {
			m.ip.Store(&address.IP)
			pc, err := net.ListenUDP(l, address)
			if err != nil {
				return nil, err
			}

			return shadowUDPPacketConn{pc}, nil
		}),
	}
	return libp2p.QUICReuse(
		func(l fx.Lifecycle, statelessResetKey quic.StatelessResetKey, tokenKey quic.TokenGeneratorKey, opts ...quicreuse.Option) (*quicreuse.ConnManager, error) {
			cm, err := quicreuse.NewConnManager(statelessResetKey, tokenKey, opts...)
			if err != nil {
				return nil, err
			}
			l.Append(fx.StopHook(func() error {
				// When we pass in our own conn manager, we need to close it manually (??)
				// TODO: this seems like a bug
				return cm.Close()
			}))
			return cm, nil
		}, quicReuseOpts...)

}

type shadowUDPPacketConn struct {
	net.PacketConn
}
