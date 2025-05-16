//go:build goexperiment.synctest

package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"testing/synctest"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	libp2pnetwork "github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/net/simconn"
	simlibp2p "github.com/libp2p/go-libp2p/p2p/net/simconn/libp2p"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	"github.com/stretchr/testify/require"
)

func TestPinwheel(t *testing.T) {
	nodeCount := 1000
	testName := "pinwheel"
	synctest.Run(func() {
		// qlogDir := fmt.Sprintf("/tmp/gossipsub-%d-%s", subnetCount, publishStrategy)
		qlogDir := ""

		const latency = 10 * time.Millisecond
		const bandwidth = 1000 * simlibp2p.OneMbps

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

		allNodesList := make([]int, nodeCount)
		for i := range allNodesList {
			allNodesList[i] = i
		}
		r := rand.New(rand.NewChaCha8([32]byte{}))
		shuffleTree := func() {
			r.Shuffle(nodeCount, func(i int, j int) {
				allNodesList[i], allNodesList[j] = allNodesList[j], allNodesList[i]
			})
		}

		differentBroadcastTreeCount := 1
		allBroadcastTrees := make([][]int, differentBroadcastTreeCount)
		for i := range allBroadcastTrees {
			// _ = shuffleTree
			shuffleTree()
			allBroadcastTrees[i] = make([]int, nodeCount)
			copy(allBroadcastTrees[i], allNodesList)
		}
		const treeBranchingFactor = 32
		getChildren := func(broadcastTree []int, nodeID int) []int {
			nodeIDPos := slices.IndexFunc(broadcastTree, func(e int) bool { return e == nodeID })
			start := min(nodeIDPos*treeBranchingFactor+1, len(broadcastTree))
			end := min(nodeIDPos*treeBranchingFactor+treeBranchingFactor, len(broadcastTree))
			return broadcastTree[start:end]
		}

		const messageSize = 1024 * 100

		const pinwheelProtocolID = "/pinwheel/0.0.1"
		var wg sync.WaitGroup
		for nodeIdx, node := range meta.Nodes {
			wg.Add(1)
			go func(nodeIdx int, node host.Host) {
				defer wg.Done()
				var receivedMessageCount atomic.Uint32

				node.SetStreamHandler(pinwheelProtocolID, func(stream libp2pnetwork.Stream) {
					defer stream.Close()

					msg := make([]byte, messageSize)
					_, err := io.ReadFull(stream, msg)
					if err != nil {
						fmt.Println("NodeIDx", nodeIdx, "error reading message:", err)
						return
					}
					if len(msg) < 2 {
						fmt.Println("NodeIDx", nodeIdx, "received invalid message:", string(msg))
						return
					}

					broadcastTreeIdx := binary.BigEndian.Uint16(msg[0:2])
					count := receivedMessageCount.Add(1)
					// if count == uint32(differentBroadcastTreeCount/2) {
					if count == uint32(differentBroadcastTreeCount) {
						fmt.Println("NodeIDx", nodeIdx, "Received Message", time.Now(), count)
					}
					// forward data to the rest of the network
					for _, child := range getChildren(allBroadcastTrees[broadcastTreeIdx], nodeIdx) {
						go func(child int) {
							s, err := node.NewStream(context.Background(), meta.Nodes[child].ID(), pinwheelProtocolID)
							if err != nil {
								fmt.Println("NodeIDx", nodeIdx, "error creating stream to child", child, ":", err)
								return
							}

							_, err = s.Write(msg)
							if err != nil {
								fmt.Println("NodeIDx", nodeIdx, "error writing message to child", child, ":", err)
							}
							s.Close()
						}(child)
					}
				})
				time.Sleep(10 * time.Second)

				ctx := context.Background()
				for _, broadcastTree := range allBroadcastTrees {
					for _, childID := range getChildren(broadcastTree, nodeIdx) {
						err := connector.ConnectTo(ctx, node, childID)
						if err != nil {
							t.Errorf("error connecting node %d to %d: %s", nodeIdx, childID, err)
						}
					}
				}

				if nodeIdx == 0 {
					for _, broadcastTree := range allBroadcastTrees {
						rootOfBroadcastTree := broadcastTree[0]
						err := connector.ConnectTo(ctx, node, rootOfBroadcastTree)
						if err != nil {
							t.Errorf("error connecting node %d to %d: %s", nodeIdx, rootOfBroadcastTree, err)
						}
					}
				}

				time.Sleep(time.Until(startTime.Add(2 * time.Minute)))
				fmt.Println(nodeIdx, "connected to", len(node.Network().Peers()), "peers at", time.Now())
				// Broadcast a message to all peers

				if nodeIdx == 0 {
					const publishCount = 2

					for i := range publishCount {

						for treeIdx, broadcastTree := range allBroadcastTrees {
							go func(treeIdx int, broadcastTree []int) {
								rootOfBroadcastTree := broadcastTree[0]
								fmt.Println("NodeIDx", nodeIdx, "Sent Message", time.Now(), "to", rootOfBroadcastTree)
								err := connector.ConnectTo(ctx, node, rootOfBroadcastTree)
								s, err := node.NewStream(context.Background(), meta.Nodes[rootOfBroadcastTree].ID(), pinwheelProtocolID)
								if err != nil {
									fmt.Println("NodeIDx", nodeIdx, "error creating stream to child", rootOfBroadcastTree, ":", err)
									return
								}
								msg := make([]byte, messageSize)
								binary.BigEndian.PutUint16(msg, uint16(treeIdx))
								s.Write(msg)
								s.Close()
							}(treeIdx, broadcastTree)
						}

						time.Sleep(time.Until(startTime.Add(time.Duration(i+1) * 30 * time.Second)))
					}
				}

				time.Sleep(2 * time.Minute)

			}(nodeIdx, node)
		}
		wg.Wait()
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
