// +build cypress

package test

import (
	"context"
	"sync"

	"github.com/testground/sdk-go/runtime"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/peer"

	"github.com/ipfs/go-datastore"
	"github.com/ipfs/go-ipns"

	kaddht "github.com/libp2p/go-libp2p-kad-dht"
	kbucket "github.com/libp2p/go-libp2p-kbucket"
	"github.com/libp2p/go-libp2p-xor/kademlia"
	"github.com/libp2p/go-libp2p-xor/key"
	"github.com/libp2p/go-libp2p-xor/trie"

	"go.uber.org/zap"
)

func createDHT(ctx context.Context, h host.Host, ds datastore.Batching, opts *SetupOpts, info *DHTNodeInfo) (*kaddht.IpfsDHT, error) {
	dhtOptions := []kaddht.Option{
		kaddht.ProtocolPrefix("/testground"),
		kaddht.V1CompatibleMode(false),
		kaddht.Datastore(ds),
		kaddht.BucketSize(opts.BucketSize),
		kaddht.RoutingTableRefreshQueryTimeout(opts.Timeout),
		kaddht.Concurrency(opts.Alpha),
		kaddht.Resiliency(opts.Beta),
		kaddht.NamespacedValidator("ipns", ipns.Validator{KeyBook: h.Peerstore()}),
	}

	if !opts.AutoRefresh {
		dhtOptions = append(dhtOptions, kaddht.DisableAutoRefresh())
	}

	if info.Properties.Bootstrapper {
		dhtOptions = append(dhtOptions, kaddht.Mode(kaddht.ModeServer))
	} else if info.Properties.Undialable && opts.ClientMode {
		dhtOptions = append(dhtOptions, kaddht.Mode(kaddht.ModeClient))
	}

	dht, err := kaddht.New(ctx, h, dhtOptions...)
	if err != nil {
		return nil, err
	}
	return dht, nil
}

func getTaggedLibp2pOpts(opts *SetupOpts, info *DHTNodeInfo) []libp2p.Option {
	if info.Properties.Bootstrapper {
		return []libp2p.Option{libp2p.EnableNATService(), libp2p.WithReachability(true)}
	} else {
		return []libp2p.Option{libp2p.EnableNATService()}
	}
}

func getAllProvRecordsNum() int { return 0 }

var (
	sqonce             sync.Once
	sqlogger, rtlogger *zap.SugaredLogger
)

func specializedTraceQuery(ctx context.Context, runenv *runtime.RunEnv, tag string) context.Context {
	sqonce.Do(func() {
		var err error
		_, sqlogger, err = runenv.CreateStructuredAsset("dht_lookups.out", runtime.StandardJSONConfig())
		if err != nil {
			runenv.RecordMessage("failed to initialize dht_lookups.out asset; nooping logger: %s", err)
			sqlogger = zap.NewNop().Sugar()
		}
		_, rtlogger, err = runenv.CreateStructuredAsset("rt_evts.out", runtime.StandardJSONConfig())
		if err != nil {
			runenv.RecordMessage("failed to initialize dht_lookups.out asset; nooping logger: %s", err)
			rtlogger = zap.NewNop().Sugar()
		}
	})

	ectx, events := kaddht.RegisterForLookupEvents(ctx)
	ectx, rtEvts := kaddht.RegisterForRoutingTableEvents(ectx)

	lookupLogger := sqlogger.With("tag", tag)
	routingTableLogger := rtlogger.With("tag", tag)

	go func() {
		for e := range events {
			lookupLogger.Infow("lookup event", "info", e)
		}
	}()

	go func() {
		for e := range rtEvts {
			routingTableLogger.Infow("rt event", "info", e)
		}
	}()

	return ectx
}

// TableHealth computes health reports for a network of nodes, whose routing contacts are given.
func TableHealth(dht *kaddht.IpfsDHT, peers map[peer.ID]*DHTNodeInfo, ri *DHTRunInfo) {
	// Construct global network view trie
	var kn []key.Key
	knownNodes := trie.New()
	for p, info := range peers {
		if info.Properties.ExpectedServer {
			k := kadPeerID(p)
			kn = append(kn, k)
			knownNodes.Add(k)
		}
	}

	rtPeerIDs := dht.RoutingTable().ListPeers()
	rtPeers := make([]key.Key, len(rtPeerIDs))
	for i, p := range rtPeerIDs {
		rtPeers[i] = kadPeerID(p)
	}

	report := kademlia.TableHealth(kadPeerID(dht.PeerID()), rtPeers, knownNodes)
	ri.RunEnv.RecordMessage("table health: %s", report.String())

	return
}

func kadPeerID(p peer.ID) key.Key {
	return key.KbucketIDToKey(kbucket.ConvertPeerID(p))
}
