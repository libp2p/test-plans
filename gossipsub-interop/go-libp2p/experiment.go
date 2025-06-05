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
	// The first 8 bytes of the message are the message ID
	return string(msg[0:8])
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
) (*scriptedNode, error) {
	slogger.Info("PeerID", "id", h.ID(), "node_id", nodeID)

	n := &scriptedNode{
		nodeID:    nodeID,
		h:         h,
		logger:    logger,
		slogger:   slogger,
		connector: connector,
		startTime: startTime,
		subCtx:    ctx,
	}
	return n, nil
}

func (n *scriptedNode) runInstruction(ctx context.Context, instruction ScriptInstruction) error {
	// Process each script instruction
	switch a := instruction.(type) {
	case InitGossipSubInstruction:
		psOpts := pubsubOptions(n.slogger, a.GossipSubParams)
		ps, err := pubsub.NewGossipSub(ctx, n.h, psOpts...)
		if err != nil {
			return err
		}
		n.pubsub = ps
	case ConnectInstruction:
		for _, targetNodeId := range a.ConnectTo {
			err := n.connector.ConnectTo(ctx, n.h, targetNodeId)
			if err != nil {
				return err
			}
		}
		n.logger.Printf("Node %d connected to %d peers", n.nodeID, len(n.h.Network().Peers()))
	case IfNodeIDEqualsInstruction:
		if a.NodeID == n.nodeID {
			n.runInstruction(ctx, a.Instruction)
		}
	case WaitUntilInstruction:
		targetTime := n.startTime.Add(time.Duration(a.ElapsedSeconds) * time.Second)
		waitTime := time.Until(targetTime)
		if waitTime > 0 {
			n.logger.Printf("Waiting %s (until elapsed: %ds)\n", waitTime, a.ElapsedSeconds)
			time.Sleep(waitTime)
		}
	case PublishInstruction:
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
	case SubscribeToTopicInstruction:
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
		return fmt.Errorf("unknown instruction type: %T", instruction)
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
	n, err := newScriptedNode(ctx, startTime, nodeId, logger, slogger, h, connector)
	if err != nil {
		return err
	}

	for _, instruction := range params.Script {
		if err := n.runInstruction(ctx, instruction); err != nil {
			return fmt.Errorf("failed to run instruction: %w", err)
		}
	}

	return nil
}
