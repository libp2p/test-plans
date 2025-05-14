//go:build goexperiment.synctest

package main

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"os"
	"sync"
	"testing"
	"testing/synctest"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/net/simconn"
	simlibp2p "github.com/libp2p/go-libp2p/p2p/net/simconn/libp2p"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	"github.com/stretchr/testify/require"
)

func TestGossipSub(t *testing.T) {
	// Read params.json
	os.ReadFile("../params.json")
	params, err := readParams("../params.json")
	require.NoError(t, err)
	nodeIDs := make(map[int]struct{})
	for _, action := range params.Script {
		switch a := action.(type) {
		case IfNodeIDEqualsAction:
			nodeIDs[a.NodeID] = struct{}{}
		}
	}
	nodeCount := len(nodeIDs)

	// Create a script with actions every 12 seconds
	runGossipSubTest(t, "gossipsub", nodeCount, params)
}

func runGossipSubTest(t *testing.T, testName string, nodeCount int, expParams ExperimentParams) {
	synctest.Run(func() {
		// qlogDir := fmt.Sprintf("/tmp/gossipsub-%d-%s", subnetCount, publishStrategy)
		qlogDir := ""

		const latency = 20 * time.Millisecond
		const bandwidth = 50 * simlibp2p.OneMbps

		network, meta, err := simlibp2p.SimpleLibp2pNetwork([]simlibp2p.NodeLinkSettingsAndCount{
			{LinkSettings: simconn.NodeBiDiLinkSettings{
				Downlink: simconn.LinkSettings{BitsPerSecond: bandwidth, Latency: latency / 2}, // Divide by two since this is latency for each direction
				Uplink:   simconn.LinkSettings{BitsPerSecond: bandwidth, Latency: latency / 2},
			}, Count: nodeCount},
		}, simlibp2p.NetworkSettings{
			UseBlankHost: true,
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

		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		folder := fmt.Sprintf("synctest-%s.data", testName)
		if _, err := os.Stat(folder); err == nil {
			os.RemoveAll(folder)
		}
		err = os.MkdirAll(folder, 0755)
		require.NoError(t, err)

		connector := newSimNetConnector(t, meta.Nodes, 2)

		// Use current time for simulation start time
		startTime := time.Now()

		var wg sync.WaitGroup
		for nodeIdx, node := range meta.Nodes {
			wg.Add(1)
			go func(nodeIdx int, node host.Host) {
				defer wg.Done()
				filename := fmt.Sprintf("%s/node%d.log", folder, nodeIdx)
				f, err := os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
				require.NoError(t, err)
				defer f.Close()
				logger := log.New(f, "", log.LstdFlags|log.Lmicroseconds)

				// Create a structured logger as well
				slogger := slog.New(slog.NewJSONHandler(f, nil))

				err = RunExperiment(ctx, startTime, logger, slogger, node, nodeIdx, connector, expParams)
				if err != nil {
					t.Errorf("error running experiment on node %d: %s", nodeIdx, err)
				}
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
