package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"log"
	"log/slog"
	"time"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/host"
)

func CalcID(msg []byte) string {
	return fmt.Sprintf("%d", binary.BigEndian.Uint64(msg))
}

type HostConnector interface {
	ConnectTo(ctx context.Context, h host.Host, targetNodeId int) error
}

type scriptedNode struct {
	nodeID    int
	h         host.Host
	logger    *log.Logger
	slogger   *slog.Logger
	connector HostConnector
	pubsub    *pubsub.PubSub
	topics    map[string]*pubsub.Topic
	startTime time.Time
	subCtx    context.Context
}

func newScriptedNode(
	ctx context.Context,
	startTime time.Time,
	nodeID int,
	logger *log.Logger,
	slogger *slog.Logger,
	h host.Host,
	connector HostConnector,
	gossipSubParams pubsub.GossipSubParams,
) (*scriptedNode, error) {
	slogger.Info("PeerID", "id", h.ID(), "node_id", nodeID)

	// create a gossipsub node and subscribe to the topic
	psOpts := pubsubOptions(slogger, gossipSubParams)
	ps, err := pubsub.NewGossipSub(ctx, h, psOpts...)
	if err != nil {
		return nil, err
	}

	n := &scriptedNode{
		nodeID:    nodeID,
		h:         h,
		logger:    logger,
		slogger:   slogger,
		connector: connector,
		pubsub:    ps,
		startTime: startTime,
		subCtx:    ctx,
	}
	return n, nil
}

func (n *scriptedNode) runAction(ctx context.Context, action ScriptAction) error {
	// Process each script action
	switch a := action.(type) {
	case ConnectAction:
		for _, targetNodeId := range a.ConnectTo {
			err := n.connector.ConnectTo(ctx, n.h, targetNodeId)
			if err != nil {
				return err
			}
		}
		n.logger.Printf("Node %d connected to %d peers", n.nodeID, len(n.h.Network().Peers()))
	case IfNodeIDEqualsAction:
		if a.NodeID == n.nodeID {
			n.runAction(ctx, a.Action)
		}
	case WaitUntilAction:
		targetTime := n.startTime.Add(time.Duration(a.ElapsedSeconds) * time.Second)
		waitTime := time.Until(targetTime)
		if waitTime > 0 {
			n.logger.Printf("Waiting %s (until elapsed: %ds)\n", waitTime, a.ElapsedSeconds)
			time.Sleep(waitTime)
		}
	case PublishAction:
		topic, err := n.getTopic(a.TopicID)
		if err != nil {
			return fmt.Errorf("failed to get topic %s: %w", a.TopicID, err)
		}

		n.logger.Printf("Publishing message %d\n", a.MessageID)
		msg := make([]byte, a.MessageSizeBytes)
		binary.BigEndian.PutUint64(msg, uint64(a.MessageID))

		if err := topic.Publish(ctx, msg); err != nil {
			return fmt.Errorf("failed to publish message %d: %w", a.MessageID, err)
		}
		n.logger.Printf("Published message %d\n", a.MessageID)
	case SubscribeToTopicAction:
		topic, err := n.getTopic(a.TopicID)
		if err != nil {
			return fmt.Errorf("failed to get topic %s: %w", a.TopicID, err)
		}
		sub, err := topic.Subscribe()
		if err != nil {
			return fmt.Errorf("failed to subscribe to topic %s: %w", a.TopicID, err)
		}
		go func() {
			for {
				n.logger.Printf("Waiting to receive message\n")
				msg, err := sub.Next(n.subCtx)
				if err == context.Canceled {
					return
				}

				if err != nil {
					n.logger.Printf("Failed to receive message: %v", err)
					return
				}
				msgID := binary.BigEndian.Uint64(msg.Data)
				n.logger.Printf("Received message %d\n", msgID)
			}
		}()
	default:
		return fmt.Errorf("unknown action type")
	}

	return nil
}

func (n *scriptedNode) getTopic(topicStr string) (*pubsub.Topic, error) {
	if n.topics == nil {
		n.topics = make(map[string]*pubsub.Topic)
	}
	t, ok := n.topics[topicStr]
	if !ok {
		var err error
		t, err = n.pubsub.Join(topicStr)
		if err != nil {
			return nil, err
		}
		n.topics[topicStr] = t
	}
	return t, nil
}

func RunExperiment(ctx context.Context, startTime time.Time, logger *log.Logger, slogger *slog.Logger, h host.Host, nodeId int, connector HostConnector, params ExperimentParams) error {
	n, err := newScriptedNode(ctx, startTime, nodeId, logger, slogger, h, connector, params.GossipSubParams)
	if err != nil {
		return err
	}

	for _, action := range params.Script {
		if err := n.runAction(ctx, action); err != nil {
			return fmt.Errorf("failed to run action: %w", err)
		}
	}

	return nil
}
