package main

import (
	"context"
	"log/slog"

	pubsub_pb "github.com/libp2p/go-libp2p-pubsub/pb"
	"github.com/libp2p/go-libp2p/core/peer"
)

type gossipTracer struct {
	logger *slog.Logger
}

func (g *gossipTracer) logMeta(action string, logger *slog.Logger, meta *pubsub_pb.TraceEvent_RPCMeta) {
	if meta == nil {
		return
	}
	for _, msg := range meta.Messages {
		logger.LogAttrs(context.Background(), slog.LevelInfo, action+" Message", slog.String("topic", msg.GetTopic()), slog.String("id", string(msg.GetMessageID())))
	}

	for _, subs := range meta.Subscription {
		logger.LogAttrs(context.Background(), slog.LevelInfo, action+" Subscription", slog.String("topic", subs.GetTopic()))
	}

	if meta.Control != nil {
		for _, graft := range meta.Control.GetGraft() {
			logger.LogAttrs(context.Background(), slog.LevelInfo, action+" Graft", slog.String("topic", graft.GetTopic()))
		}
		for _, prune := range meta.Control.GetPrune() {
			logger.LogAttrs(context.Background(), slog.LevelInfo, action+" Prune", slog.String("topic", prune.GetTopic()))
		}
	}
}

// Trace implements pubsub.EventTracer.
func (g *gossipTracer) Trace(evt *pubsub_pb.TraceEvent) {
	switch *evt.Type {
	case pubsub_pb.TraceEvent_RECV_RPC:
		recv := evt.GetRecvRPC()
		from := peer.ID(recv.ReceivedFrom)
		logger := g.logger.With(slog.String("from", from.String()))
		g.logMeta("Received", logger, recv.Meta)
	case pubsub_pb.TraceEvent_SEND_RPC:
		send := evt.GetSendRPC()
		to := peer.ID(send.GetSendTo())
		logger := g.logger.With(slog.String("to", to.String()))
		g.logMeta("Sent", logger, send.GetMeta())
	}
}
