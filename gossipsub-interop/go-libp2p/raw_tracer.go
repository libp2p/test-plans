package main

import (
	"log/slog"

	pubsub "github.com/libp2p/go-libp2p-pubsub"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
)

func logValue(rpc *pubsub.RPC) slog.Value {
	// Messages
	var msgs []any
	for _, msg := range rpc.Publish {
		msgs = append(msgs, slog.Group(
			"message",
			slog.Any("dataPrefix", msg.Data[0:min(len(msg.Data), 32)]),
			slog.Any("dataLen", len(msg.Data)),
		))
	}

	var fields []slog.Attr
	if len(msgs) > 0 {
		fields = append(fields, slog.Group("publish", msgs...))
	}
	if rpc.Control != nil {
		fields = append(fields, slog.Any("control", rpc.Control))
	}
	if rpc.Subscriptions != nil {
		fields = append(fields, slog.Any("subscriptions", rpc.Subscriptions))
	}
	if rpc.TestExtension != nil {
		fields = append(fields, slog.Any("testExtension", rpc.TestExtension))
	}
	return slog.GroupValue(fields...)
}

type rawTracer struct {
	logger *slog.Logger
}

var _ pubsub.RawTracer = (*rawTracer)(nil)

// DropRPC implements pubsub.RawTracer.
func (t *rawTracer) DropRPC(rpc *pubsub.RPC, p peer.ID) {
	t.logger.Info("Dropped RPC", "rpc", logValue(rpc))
}

// RecvRPC implements pubsub.RawTracer.
func (t *rawTracer) RecvRPC(rpc *pubsub.RPC) {
	t.logger.Info("Received RPC", "rpc", logValue(rpc))
}

// SendRPC implements pubsub.RawTracer.
func (t *rawTracer) SendRPC(rpc *pubsub.RPC, p peer.ID) {
	t.logger.Info("Send RPC", "rpc", logValue(rpc), "to", p)
}

// AddPeer implements pubsub.RawTracer.
func (t *rawTracer) AddPeer(p peer.ID, proto protocol.ID) {
}

// DeliverMessage implements pubsub.RawTracer.
func (t *rawTracer) DeliverMessage(msg *pubsub.Message) {
}

// DuplicateMessage implements pubsub.RawTracer.
func (t *rawTracer) DuplicateMessage(msg *pubsub.Message) {
}

// Graft implements pubsub.RawTracer.
func (t *rawTracer) Graft(p peer.ID, topic string) {
}

// Join implements pubsub.RawTracer.
func (t *rawTracer) Join(topic string) {
}

// Leave implements pubsub.RawTracer.
func (t *rawTracer) Leave(topic string) {
}

// Prune implements pubsub.RawTracer.
func (t *rawTracer) Prune(p peer.ID, topic string) {
}

// RejectMessage implements pubsub.RawTracer.
func (t *rawTracer) RejectMessage(msg *pubsub.Message, reason string) {
}

// RemovePeer implements pubsub.RawTracer.
func (t *rawTracer) RemovePeer(p peer.ID) {
}

// ThrottlePeer implements pubsub.RawTracer.
func (t *rawTracer) ThrottlePeer(p peer.ID) {
}

// UndeliverableMessage implements pubsub.RawTracer.
func (t *rawTracer) UndeliverableMessage(msg *pubsub.Message) {
}

// ValidateMessage implements pubsub.RawTracer.
func (t *rawTracer) ValidateMessage(msg *pubsub.Message) {
}
