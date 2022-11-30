package main

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"golang.org/x/sync/errgroup"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"

	"github.com/testground/sdk-go/network"
	"github.com/testground/sdk-go/run"
	"github.com/testground/sdk-go/runtime"
	"github.com/testground/sdk-go/sync"
)

// A test plan is just a standard Go program which receives a bunch of
// environment variables to configure itself. A test plan ONLY depends on the
// lightweight Testground SDK (https://github.com/testground/sdk-go/).
//
// A central object is the RunEnv (runtime environment), which encapsulates the
// contract between Testground and this test plan. Read more: https://docs.testground.ai/concepts-and-architecture/runtime.
//
// Other key objects are:
//
//   - sync.Client (https://pkg.go.dev/github.com/testground/sdk-go/sync):
//     used to coordinate instances with one another via synchronisations
//     primitives like signals, barriers, pubsub. In the future, we plan to
//     support more sophisticated patterns like locks, semaphores, etc.
//   - network.Client (https://pkg.go.dev/github.com/testground/sdk-go/network):
//     used to manipulate network configurations. The network.Client uses the
//     sync service to communicate with the sidecar containers that manage
//     the network configurations "from the outside". In other words, network
//     configuration is NOT managed locally by the SDK. Rather, the SDK sends
//     commands to the sidecar, and awaits until those commands are applied.
func main() {
	// Delegate this run to the SDK.
	run.Invoke(run.InitializedTestCaseFn(runPing))
}

// runPing is the test case logic.
//
// Its signature conforms to the SDK's run.InitializedTestCaseFn type. As a
// result, the Testground SDK will perform a few useful preparation steps
// for us:
//
//  1. Initializing a sync client, bound to this runenv. Refer to the main()
//     docs for more info.
//  2. Initializing a net client, using the above sync client. Refer to the
//     main() docs for more info.
//  3. Waiting for the network to initialize.
//  4. Claiming a global sequence number, which uniquely identifies this instance within the run.
//  5. Claiming a group-scoped sequence number, which uniquely identifies this instance within its group.
func runPing(runenv *runtime.RunEnv, initCtx *run.InitContext) error {
	// 📝  Consume test parameters from the runtime environment.
	var (
		// TODO consume secure_channel
		// secureChannel = runenv.StringParam("secure_channel")
		maxLatencyMs = runenv.IntParam("max_latency_ms")
		iterations   = runenv.IntParam("iterations")
	)

	// We can record messages anytime; RecordMessage supports fmt-style
	// formatting strings.
	runenv.RecordMessage("started test instance; params: max_latency_ms=%d, iterations=%d", maxLatencyMs, iterations)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()

	// 🐣  Wait until all instances in this test run have signalled.
	//
	// This is API sugar for waiting until all runenv.TestInstanceCount signals
	// have been made on state "initialized_global" (run.StateInitializedGlobal).
	//
	// By convention, Must* methods in the testground SDK will panic upon error.
	//
	// The sdk's run.Invoke* entrypoint functions catch these panics, record a
	// CRASH event, and abort the test immediately.
	initCtx.MustWaitAllInstancesInitialized(ctx)

	// 🐥  Now all instances are ready for action.
	//
	// Note: In large test runs, the scheduler might take a few minutes to
	// schedule all instances in a cluster.

	// In containerised runs (local:docker, cluster:k8s runners), Testground
	// instances get attached two networks:
	//
	//   * a data network
	//   * a control network
	//
	// The data network is where standard test traffic flows. The control
	// network connects us ONLY with the sync service, InfluxDB, etc. All
	// traffic shaping rules are applied to the data network. Thanks to this
	// separation, we can simulate disconnected scenarios by detaching the data
	// network adapter, or blocking all incoming/outgoing traffic on that
	// network.
	//
	// We need to listen on (and advertise) our data network IP address, so we
	// obtain it from the NetClient.
	ip := initCtx.NetClient.MustGetDataNetworkIP()

	// ☎️  Let's construct the libp2p node.
	listenAddr := fmt.Sprintf("/ip4/%s/tcp/0", ip)
	host, err := libp2p.New(libp2p.ListenAddrStrings(listenAddr))

	if err != nil {
		return fmt.Errorf("failed to instantiate libp2p instance: %w", err)
	}
	defer host.Close()

	// 🚧  Now we instantiate the ping service.
	//
	// This adds a stream handler to our Host so it can process inbound pings,
	// and the returned PingService instance allows us to perform outbound pings.
	ping := ping.NewPingService(host)

	// Record our listen addrs.
	runenv.RecordMessage("my listen addrs: %v", host.Addrs())

	// Obtain our own address info, and use the sync service to publish it to a
	// 'peersTopic' topic, where others will read from.
	var (
		hostId = host.ID()
		ai     = &peer.AddrInfo{ID: hostId, Addrs: host.Addrs()}

		// the peers topic where all instances will advertise their AddrInfo.
		peersTopic = sync.NewTopic("peers", new(peer.AddrInfo))

		// initialize a slice to store the AddrInfos of all other peers in the run.
		peers = make([]*peer.AddrInfo, 0, runenv.TestInstanceCount)
	)

	// Publish our own.
	initCtx.SyncClient.MustPublish(ctx, peersTopic, ai)

	// Now subscribe to the peers topic and consume all addresses, storing them
	// in the peers slice.
	peersCh := make(chan *peer.AddrInfo)
	sctx, scancel := context.WithCancel(ctx)
	sub := initCtx.SyncClient.MustSubscribe(sctx, peersTopic, peersCh)

	// Receive the expected number of AddrInfos.
	for len(peers) < cap(peers) {
		select {
		case ai := <-peersCh:
			peers = append(peers, ai)
		case err := <-sub.Done():
			return err
		}
	}
	scancel() // cancels the Subscription.

	// ✨
	// ✨  Now we know about all other libp2p hosts in this test.
	// ✨

	// This is a closure that pings all peers in the test in parallel, and
	// records the latency value as a message and as a result datapoint.
	pingPeers := func(tag string) error {
		g, gctx := errgroup.WithContext(ctx)
		for _, ai := range peers {
			if ai.ID == hostId {
				continue
			}

			id := ai.ID // capture the ID locally for safe use within the closure.

			g.Go(func() error {
				// a context for the continuous stream of pings.
				pctx, cancel := context.WithCancel(gctx)
				defer cancel()
				res := <-ping.Ping(pctx, id)
				if res.Error != nil {
					return res.Error
				}

				// record a message.
				runenv.RecordMessage("ping result (%s) from peer %s: %s", tag, id, res.RTT)

				// record a result point; these points will be batch-inserted
				// into InfluxDB when the test concludes.
				//
				// ping-result is the metric name, and round and peer are tags.
				point := fmt.Sprintf("ping-result,round=%s,peer=%s", tag, id)
				runenv.R().RecordPoint(point, float64(res.RTT.Milliseconds()))
				return nil
			})
		}
		return g.Wait()
	}

	// ☎️  Connect to all other peers.
	//
	// Note: we sidestep simultaneous connect issues by ONLY connecting to peers
	// who published their addresses before us (this is enough to dedup and avoid
	// two peers dialling each other at the same time).
	//
	// We can do this because sync service pubsub is ordered.
	for _, ai := range peers {
		if ai.ID == hostId {
			break
		}
		runenv.RecordMessage("Dial peer: %s", ai.ID)
		if err := host.Connect(ctx, *ai); err != nil {
			return err
		}
	}

	runenv.RecordMessage("done dialling my peers")

	// Wait for all peers to signal that they're done with the connection phase.
	initCtx.SyncClient.MustSignalAndWait(ctx, "connected", runenv.TestInstanceCount)

	// 📡  Let's ping all our peers without any traffic shaping rules.
	if err := pingPeers("initial"); err != nil {
		return err
	}

	// 🕐  Wait for all peers to have finished the initial round.
	initCtx.SyncClient.MustSignalAndWait(ctx, "initial", runenv.TestInstanceCount)

	// 🎉 🎉 🎉
	//
	// Here is where the fun begins. We will perform `iterations` rounds of
	// randomly altering our network latency, waiting for all other peers to
	// do too. We will record our observations for each round.
	//
	// 🎉 🎉 🎉

	// Let's initialize the random seed to the current timestamp + our global sequence number.
	// Otherwise all instances will end up generating the same "random" latencies 🤦‍
	rand.Seed(time.Now().UnixNano() + initCtx.GlobalSeq)

	for i := 1; i <= iterations; i++ {
		runenv.RecordMessage("⚡️  ITERATION ROUND %d", i)

		// 🤹  Let's calculate our new latency.
		latency := time.Duration(rand.Int31n(int32(maxLatencyMs))) * time.Millisecond
		runenv.RecordMessage("(round %d) my latency: %s", i, latency)

		// 🐌  Let's ask the NetClient to reconfigure our network.
		//
		// The sidecar will apply the network latency from the outside, and will
		// signal on the CallbackState in the sync service. Since we want to wait
		// for ALL instances to configure their networks for this round before
		// we proceed, we set the CallbackTarget to the total number of instances
		// partitipating in this test run. MustConfigureNetwork will block until
		// that many signals have been received. We use a unique state ID for
		// each round.
		//
		// Read more about the sidecar: https://docs.testground.ai/concepts-and-architecture/sidecar
		initCtx.NetClient.MustConfigureNetwork(ctx, &network.Config{
			Network:        "default",
			Enable:         true,
			Default:        network.LinkShape{Latency: latency},
			CallbackState:  sync.State(fmt.Sprintf("network-configured-%d", i)),
			CallbackTarget: runenv.TestInstanceCount,
		})

		if err := pingPeers(fmt.Sprintf("iteration-%d", i)); err != nil {
			return err
		}

		// Signal that we're done with this round and wait for others to be
		// done before we repeat and switch our latencies, or exit the loop and
		// close the host.
		doneState := sync.State(fmt.Sprintf("done-%d", i))
		initCtx.SyncClient.MustSignalAndWait(ctx, doneState, runenv.TestInstanceCount)
	}

	_ = host.Close()
	return nil
}
