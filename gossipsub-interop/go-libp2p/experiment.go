package main

import (
	"context"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"log"
	"log/slog"
	"time"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p-pubsub/partialmessages"
	pubsub_pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
)

func CalcID(msg []byte) string {
	// The first 8 bytes of the message are the message ID
	return string(msg[0:8])
}

type HostConnector interface {
	ConnectTo(ctx context.Context, h host.Host, targetNodeId int) error
}

type incomingPartialRPC struct {
	pubsub_pb.PartialMessagesExtension
	from peer.ID
}

type partialMsgWithTopic struct {
	topic string
	msg   *PartialMessage
}
type publishReq struct {
	topic          string
	groupID        []byte
	publishToPeers []peer.ID
}

type partialMsgManager struct {
	*slog.Logger
	// Close this channel to terminate the manager
	done        chan struct{}
	incomingRPC chan incomingPartialRPC
	publish     chan publishReq
	add         chan partialMsgWithTopic
	// map -> topic -> groupID -> *PartialMessage
	partialMessages map[string]map[string]*PartialMessage

	pubsub *pubsub.PubSub
}

func (m *partialMsgManager) start(logger *slog.Logger, pubsub *pubsub.PubSub) {
	m.Logger = logger
	m.done = make(chan struct{})
	m.incomingRPC = make(chan incomingPartialRPC, 64)
	m.publish = make(chan publishReq)
	m.add = make(chan partialMsgWithTopic)
	m.partialMessages = make(map[string]map[string]*PartialMessage)
	m.pubsub = pubsub
	go m.run()
}
func (m *partialMsgManager) close() {
	if m.done != nil {
		close(m.done)
	}
}

func (m *partialMsgManager) run() {
	for {
		select {
		case rpc := <-m.incomingRPC:
			m.Info("Received partial RPC")
			m.handleRPC(rpc)
		case req := <-m.add:
			m.Info("Adding partial message")
			m.addMsg(req)
		case req := <-m.publish:
			pm := m.partialMessages[req.topic][string(req.groupID)]
			m.Info("publishing partial message", "groupID", hex.EncodeToString(pm.GroupID()), "topic", req.topic)
			opts := partialmessages.PublishOptions{
				PublishToPeers: req.publishToPeers,
			}
			err := m.pubsub.PublishPartialMessage(req.topic, pm, opts)
			if err != nil {
				panic(err)
			}
		case <-m.done:
			return
		}
	}
}

func (m *partialMsgManager) addMsg(req partialMsgWithTopic) {
	_, ok := m.partialMessages[req.topic]
	if !ok {
		m.partialMessages[req.topic] = make(map[string]*PartialMessage)
	}
	_, ok = m.partialMessages[req.topic][string(req.msg.GroupID())]
	if !ok {
		m.partialMessages[req.topic][string(req.msg.GroupID())] = req.msg
	}
}

func (m *partialMsgManager) handleRPC(rpc incomingPartialRPC) {
	_, ok := m.partialMessages[rpc.GetTopicID()]
	if !ok {
		m.partialMessages[rpc.GetTopicID()] = make(map[string]*PartialMessage)
	}

	pm, existingMessage := m.partialMessages[rpc.GetTopicID()][string(rpc.GroupID)]
	if !existingMessage {
		pm = &PartialMessage{}
		copy(pm.groupID[:], rpc.GroupID)
		m.partialMessages[rpc.GetTopicID()][string(rpc.GroupID)] = pm
	}

	// Extend first, so we don't request something we just got.
	beforeExtend := pm.PartsMetadata()[0]
	if len(rpc.PartialMessage) != 0 {
		err := pm.Extend(rpc.PartialMessage)
		if err != nil {
			m.Error("Failed to extend partial message", "err", err)
			return
		}
	}
	afterExtend := pm.PartsMetadata()[0]
	var extended bool
	if beforeExtend != afterExtend {
		m.Info("Extended partial message")
		extended = true

	}

	gid := binary.BigEndian.Uint64(rpc.GroupID)
	if extended && pm.complete() {
		m.Info("All parts received", "group id", gid)
	}

	pmHas := pm.PartsMetadata()
	var shouldRequest bool
	if len(rpc.PartsMetadata) == 1 {
		shouldRequest = pmHas[0] != rpc.PartsMetadata[0]
		if shouldRequest {
			m.Info("Republishing partial message because parts metadata are different")
		}
	}

	if extended || shouldRequest || !existingMessage {
		err := m.pubsub.PublishPartialMessage(rpc.GetTopicID(), pm, partialmessages.PublishOptions{})
		if err != nil {
			panic(err)
		}
	}
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

	partialMsgMgr partialMsgManager
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

func (n *scriptedNode) close() error {
	n.partialMsgMgr.close()
	return nil
}

func (n *scriptedNode) runInstruction(ctx context.Context, instruction ScriptInstruction) error {
	// Process each script instruction
	switch a := instruction.(type) {
	case InitGossipSubInstruction:
		slog.SetLogLoggerLevel(slog.LevelDebug)
		pme := &partialmessages.PartialMessagesExtension{
			Logger: n.slogger,
			ValidateRPC: func(from peer.ID, rpc *pubsub_pb.PartialMessagesExtension) error {
				// Not doing any validation for now
				return nil
			},
			OnIncomingRPC: func(from peer.ID, rpc *pubsub_pb.PartialMessagesExtension) error {
				n.partialMsgMgr.incomingRPC <- incomingPartialRPC{
					from:                     from,
					PartialMessagesExtension: *rpc,
				}
				return nil
			},
			MergePartsMetadata: MergeMetadata,
		}

		psOpts := pubsubOptions(n.slogger, a.GossipSubParams, pme)
		ps, err := pubsub.NewGossipSub(ctx, n.h, psOpts...)
		if err != nil {
			return err
		}
		n.pubsub = ps
		n.partialMsgMgr.start(n.slogger, ps)
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
			err := n.runInstruction(ctx, a.Instruction)
			if err != nil {
				return err
			}
		}
	case WaitUntilInstruction:
		targetTime := n.startTime.Add(time.Duration(a.ElapsedSeconds) * time.Second)
		waitTime := time.Until(targetTime)
		if waitTime > 0 {
			n.logger.Printf("Waiting %s (until elapsed: %ds)\n", waitTime, a.ElapsedSeconds)
			time.Sleep(waitTime)
		}
	case PublishInstruction:
		topic, err := n.getTopic(a.TopicID, false)
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
		topic, err := n.getTopic(a.TopicID, a.Partial)
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
	case SetTopicValidationDelayInstruction:
		n.pubsub.RegisterTopicValidator(a.TopicID, func(context.Context, peer.ID, *pubsub.Message) pubsub.ValidationResult {
			duration := time.Duration(a.DelaySeconds * float64(time.Second))
			time.Sleep(duration)
			return pubsub.ValidationAccept
		})

	case AddPartialMessage:
		pm := &PartialMessage{
			eagerPushParts: byte(a.EagerPushParts),
		}
		binary.BigEndian.AppendUint64(pm.groupID[:0], uint64(a.GroupID))
		pm.FillParts(uint8(a.Parts))
		if pm.complete() {
			n.slogger.Info("All parts received", "group id", uint64(a.GroupID))
		}
		n.partialMsgMgr.add <- partialMsgWithTopic{
			topic: a.TopicID,
			msg:   pm,
		}

	case PublishPartialInstruction:
		var groupID [8]byte
		binary.BigEndian.AppendUint64(groupID[:0], uint64(a.GroupID))
		var publishToPeers []peer.ID
		if len(a.PublishToNodeIDs) > 0 {
			publishToPeers = make([]peer.ID, 0, len(a.PublishToNodeIDs))
			for _, targetNodeID := range a.PublishToNodeIDs {
				peerID, err := peer.IDFromPrivateKey(nodePrivKey(targetNodeID))
				if err != nil {
					return fmt.Errorf("failed to derive peer ID for node %d: %w", targetNodeID, err)
				}
				publishToPeers = append(publishToPeers, peerID)
			}
		}
		n.partialMsgMgr.publish <- publishReq{
			topic:          a.TopicID,
			groupID:        groupID[:],
			publishToPeers: publishToPeers,
		}

	default:
		return fmt.Errorf("unknown instruction type: %T", instruction)
	}

	return nil
}

func (n *scriptedNode) getTopic(topicStr string, partial bool) (*pubsub.Topic, error) {
	if n.topics == nil {
		n.topics = make(map[string]*pubsub.Topic)
	}
	t, ok := n.topics[topicStr]
	if !ok {
		var err error
		var opts []pubsub.TopicOpt
		if partial {
			opts = append(opts, pubsub.RequestPartialMessages())
		}
		t, err = n.pubsub.Join(topicStr, opts...)
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
	defer n.close()

	for _, instruction := range params.Script {
		if err := n.runInstruction(ctx, instruction); err != nil {
			return fmt.Errorf("failed to run instruction: %w", err)
		}
	}

	return nil
}
