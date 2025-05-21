//go:build goexperiment.synctest

package main

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	packethost "github.com/libp2p/go-libp2p/p2p/host/packet"
	"github.com/libp2p/go-libp2p/p2p/net/simconn"
	simlibp2p "github.com/libp2p/go-libp2p/p2p/net/simconn/libp2p"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	"github.com/stretchr/testify/require"
)

const pinwheelProtocolID = "/pinwheel/0.0.1"

type tree []int

func newTree(nodeCount int) tree {
	t := make([]int, nodeCount)
	for i := range t {
		t[i] = i
	}
	return t
}

func (t tree) shuffle(r *rand.Rand) {
	r.Shuffle(len(t), func(i int, j int) {
		t[i], t[j] = t[j], t[i]
	})
}

func (t tree) children(treeBranchingFactor, id int) []int {
	nodeIDPos := slices.IndexFunc(t, func(e int) bool { return e == id })
	start := min(nodeIDPos*treeBranchingFactor+1, len(t))
	end := min(nodeIDPos*treeBranchingFactor+treeBranchingFactor, len(t))
	return t[start:end]
}

func (t tree) clone() tree {
	return slices.Clone(t)
}

func TestPinwheel(t *testing.T) {
	const nodeCount = 1_000
	const treeBranchingFactor = 32
	const chunkSize = 1 << 10
	const chunkCount = 64

	const publishCount = 1

	const latency = 10 * time.Millisecond
	const bandwidth = 1000 * simlibp2p.OneMbps

	testStart := time.Now()
	testName := "pinwheel"
	synctest.Run(func() {
		qlogDir := fmt.Sprintf("/tmp/pinwheel/%s", testStart.Format(time.RFC3339))
		// qlogDir := ""

		var firstPublishTime time.Time
		var lastPublishTimeMu sync.Mutex
		var lastPublishTime time.Time

		network, meta, err := simlibp2p.SimpleLibp2pNetwork([]simlibp2p.NodeLinkSettingsAndCount{
			{LinkSettings: simconn.NodeBiDiLinkSettings{
				Downlink: simconn.LinkSettings{BitsPerSecond: bandwidth, Latency: latency / 2}, // Divide by two since this is latency for each direction
				Uplink:   simconn.LinkSettings{BitsPerSecond: bandwidth, Latency: latency / 2},
			}, Count: nodeCount},
		}, simlibp2p.NetworkSettings{
			QUICReuseOptsForHostIdx: func(idx int) []quicreuse.Option {
				if idx == 0 && qlogDir != "" {
					return []quicreuse.Option{
						quicreuse.WithQlogDir(qlogDir),
					}
				}
				return nil
			},
		})
		require.NoError(t, err)
		network.Start()
		defer network.Close()

		defer func() {
			for _, node := range meta.Nodes {
				node.Close()
			}
		}()

		folder := fmt.Sprintf("synctest-%s.data", testName)
		if _, err := os.Stat(folder); err == nil {
			os.RemoveAll(folder)
		}
		err = os.MkdirAll(folder, 0755)
		require.NoError(t, err)

		connector := newSimNetConnector(t, meta.Nodes, 2)

		// Use current time for simulation start time
		startTime := time.Now()

		r := rand.New(rand.NewChaCha8([32]byte{}))
		allBroadcastTrees := make([]tree, chunkCount)
		for i := range allBroadcastTrees {
			t := newTree(nodeCount)
			t.shuffle(r)
			allBroadcastTrees[i] = t
		}

		var wg sync.WaitGroup
		for nodeIdx, node := range meta.Nodes {
			wg.Add(1)
			go func(nodeIdx int, node host.Host) {
				defer wg.Done()
				var recvdChunkCount atomic.Uint32

				ph := packethost.Host{
					Network: node.Network(),
				}
				ph.Start()
				defer ph.Close()

				ctx, cancel := context.WithCancel(context.Background())
				defer cancel()

				// Initial discovery.
				// With 0rtt we'd be able to close these connections later and still send 0rtt datagrams .
				for _, broadcastTree := range allBroadcastTrees {
					for _, childID := range broadcastTree.children(treeBranchingFactor, nodeIdx) {
						err := connector.ConnectTo(ctx, node, childID)
						if err != nil {
							t.Errorf("error connecting node %d to %d: %s", nodeIdx, childID, err)
						}
					}
				}

				// The publisher (nodeIdx = 0) will connect to the root of all broadcast trees
				if nodeIdx == 0 {
					for _, broadcastTree := range allBroadcastTrees {
						rootOfBroadcastTree := broadcastTree[0]
						err := connector.ConnectTo(ctx, node, rootOfBroadcastTree)
						if err != nil {
							t.Errorf("error connecting node %d to %d: %s", nodeIdx, rootOfBroadcastTree, err)
						}
					}
				}

				// Handle datagrams and forward
				go func() {
					for {
						// Handle inbound datagrams
						_, msg, err := ph.ReceiveDatagram(ctx, pinwheelProtocolID)
						if err != nil {
							if errors.Is(err, context.Canceled) {
								return
							}
							fmt.Println("NodeIDx", nodeIdx, "error reading message:", err)
							return
						}
						if len(msg) < 2 {
							fmt.Println("NodeIDx", nodeIdx, "received invalid message:", string(msg))
							return
						}

						broadcastTreeIdx := binary.BigEndian.Uint16(msg[0:2])
						recvCount := recvdChunkCount.Add(1)

						if nodeIdx != 0 && recvCount >= uint32(chunkCount/2) {
							// fmt.Println("NodeIDx", nodeIdx, "Received Message", time.Now(), count)

							// Update our stats
							lastPublishTimeMu.Lock()
							now := time.Now()
							if lastPublishTime.IsZero() || lastPublishTime.Before(now) {
								lastPublishTime = now
							}
							lastPublishTimeMu.Unlock()
						}

						// forward data to the rest of the network
						for _, child := range allBroadcastTrees[broadcastTreeIdx].children(treeBranchingFactor, nodeIdx) {
							go func(child int) {
								msg := make([]byte, chunkSize)
								err = ph.SendDatagram(ctx, pinwheelProtocolID, meta.Nodes[child].ID(), msg)
								if err != nil {
									fmt.Println("NodeIDx", nodeIdx, "error writing message to child", child, ":", err)
									return
								}
							}(child)
						}
					}
				}()

				time.Sleep(time.Until(startTime.Add(time.Minute)))

				// Publisher publishes
				if nodeIdx == 0 {
					for i := range publishCount {
						lastPublishTimeMu.Lock()
						if !lastPublishTime.IsZero() {
							fmt.Println("Publishing took", lastPublishTime.Sub(firstPublishTime))
						}
						lastPublishTimeMu.Unlock()

						firstPublishTime = time.Now()
						for treeIdx, broadcastTree := range allBroadcastTrees {
							go func(treeIdx int, broadcastTree []int) {
								rootOfBroadcastTree := broadcastTree[0]
								fmt.Println("NodeIDx", nodeIdx, "Sent Message", time.Now(), "to", rootOfBroadcastTree)
								msg := make([]byte, chunkSize)
								binary.BigEndian.PutUint16(msg, uint16(treeIdx))
								ph.SendDatagram(context.Background(), pinwheelProtocolID, meta.Nodes[rootOfBroadcastTree].ID(), msg)
								if err != nil {
									fmt.Println("NodeIDx", nodeIdx, "error sending msg", rootOfBroadcastTree, ":", err)
									return
								}
							}(treeIdx, broadcastTree)
						}
						time.Sleep(time.Until(startTime.Add(time.Duration(i+1) * 30 * time.Second)))
					}
				}

				time.Sleep(2 * time.Minute)
			}(nodeIdx, node)
		}
		wg.Wait()

		lastPublishTimeMu.Lock()
		if !lastPublishTime.IsZero() {
			fmt.Println("Publishing took", lastPublishTime.Sub(firstPublishTime))
		}
		lastPublishTimeMu.Unlock()
	})
}

type SimNetConnector struct {
	t        *testing.T
	allNodes []host.Host
}

func newSimNetConnector(t *testing.T, allNodes []host.Host, connectorConcurrency int) *SimNetConnector {
	return &SimNetConnector{
		t:        t,
		allNodes: allNodes,
	}
}

func (c *SimNetConnector) ConnectTo(ctx context.Context, h host.Host, targetNodeID int) error {
	if targetNodeID < 0 || targetNodeID >= len(c.allNodes) {
		return fmt.Errorf("target node ID %d out of range [0, %d)", targetNodeID, len(c.allNodes))
	}

	targetNode := c.allNodes[targetNodeID]

	// Don't connect to self
	if h.ID() == targetNode.ID() {
		return nil
	}

	err := h.Connect(ctx, peer.AddrInfo{ID: targetNode.ID(), Addrs: targetNode.Addrs()})
	if err != nil {
		c.t.Logf("error connecting to node %d: %s", targetNodeID, err)
		return err
	}

	return nil
}
