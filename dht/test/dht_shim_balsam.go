//go:build balsam
// +build balsam

package test

import (
	"context"

	"github.com/ipfs/go-datastore"
	"github.com/ipfs/go-ipns"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p-core/host"
	"github.com/libp2p/go-libp2p-core/peer"
	kaddht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/testground/sdk-go/runtime"
)

func createDHT(ctx context.Context, h host.Host, ds datastore.Batching, opts *SetupOpts, info *DHTNodeInfo) (*kaddht.IpfsDHT, error) {
	dhtOptions := []kaddht.Option{
		kaddht.ProtocolPrefix("/testground/kad/1.0.0"),
		kaddht.Datastore(ds),
		kaddht.BucketSize(opts.BucketSize),
		kaddht.RoutingTableRefreshQueryTimeout(opts.Timeout),
		kaddht.NamespacedValidator("ipns", ipns.Validator{KeyBook: h.Peerstore()}),
	}

	if !opts.AutoRefresh {
		dhtOptions = append(dhtOptions, kaddht.DisableAutoRefresh())
	}

	if info.Properties.Undialable && opts.ClientMode {
		dhtOptions = append(dhtOptions, kaddht.Mode(kaddht.ModeClient))
	}

	dht, err := kaddht.New(ctx, h, dhtOptions...)
	if err != nil {
		return nil, err
	}
	return dht, nil
}

func getTaggedLibp2pOpts(opts *SetupOpts, info *DHTNodeInfo) []libp2p.Option { return nil }

func getAllProvRecordsNum() int { return 1000 }

func specializedTraceQuery(ctx context.Context, runenv *runtime.RunEnv, tag string) context.Context {
	return ctx
}

func TableHealth(dht *kaddht.IpfsDHT, peers map[peer.ID]*DHTNodeInfo, ri *DHTRunInfo) {}
