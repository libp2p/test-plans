// +build hardened_api
// The hardened_api build tag should be used when targeting a version of go-libp2p-pubsub after
// GossipSub v1.1.0 was introduced.

package main

import (
	"fmt"

	"github.com/libp2p/go-libp2p-core/peer"
	pubsub "github.com/libp2p/go-libp2p-pubsub"
)

func pubsubOptions(cfg PubsubNodeConfig) ([]pubsub.Option, error) {
	opts := []pubsub.Option{
		pubsub.WithEventTracer(cfg.Tracer),
		pubsub.WithFloodPublish(cfg.FloodPublishing),
		scoreParamsOption(cfg.PeerScoreParams),
	}

	if cfg.PeerScoreInspect.Inspect != nil && cfg.PeerScoreInspect.Period != 0 {
		opts = append(opts, pubsub.WithPeerScoreInspect(cfg.PeerScoreInspect.Inspect, cfg.PeerScoreInspect.Period))
	}

	if cfg.ValidateQueueSize > 0 {
		opts = append(opts, pubsub.WithValidateQueueSize(cfg.ValidateQueueSize))
	}

	if cfg.OutboundQueueSize > 0 {
		opts = append(opts, pubsub.WithPeerOutboundQueueSize(cfg.OutboundQueueSize))
	}

	// Set the overlay parameters
	if cfg.OverlayParams.d >= 0 {
		pubsub.GossipSubD = cfg.OverlayParams.d
	}
	if cfg.OverlayParams.dlo >= 0 {
		pubsub.GossipSubDlo = cfg.OverlayParams.dlo
	}
	if cfg.OverlayParams.dhi >= 0 {
		pubsub.GossipSubDhi = cfg.OverlayParams.dhi
	}
	if cfg.OverlayParams.dscore >= 0 {
		pubsub.GossipSubDscore = cfg.OverlayParams.dscore
	}
	if cfg.OverlayParams.dlazy >= 0 {
		pubsub.GossipSubDlazy = cfg.OverlayParams.dlazy
	}
	if cfg.OverlayParams.gossipFactor > 0 {
		pubsub.GossipSubGossipFactor = cfg.OverlayParams.gossipFactor
	}

	// set opportunistic graft params
	if cfg.OpportunisticGraftTicks > 0 {
		pubsub.GossipSubOpportunisticGraftTicks = uint64(cfg.OpportunisticGraftTicks)
	}

	return opts, nil
}

// TODO: implement app-specific scoring
func applicationScore(id peer.ID) float64 {
	return 1.0
}

func scoreParamsOption(params ScoreParams) pubsub.Option {
	topicParams := make(map[string]*pubsub.TopicScoreParams, len(params.Topics))
	for name, t := range params.Topics {
		topicParams[name] = convertTopicParams(t)
	}
	psp := pubsub.PeerScoreParams{
		Topics: topicParams,

		AppSpecificScore:  applicationScore,
		AppSpecificWeight: 0,

		IPColocationFactorWeight:    params.IPColocationFactorWeight,
		IPColocationFactorThreshold: params.IPColocationFactorThreshold,
		DecayInterval:               params.DecayInterval.Duration,
		DecayToZero:                 params.DecayToZero,
		RetainScore:                 params.RetainScore.Duration,
	}
	pst := pubsub.PeerScoreThresholds{
		GossipThreshold:             params.Thresholds.GossipThreshold,
		PublishThreshold:            params.Thresholds.PublishThreshold,
		GraylistThreshold:           params.Thresholds.GraylistThreshold,
		AcceptPXThreshold:           params.Thresholds.AcceptPXThreshold,
		OpportunisticGraftThreshold: params.Thresholds.OpportunisticGraftThreshold,
	}

	fmt.Printf("peer score params: %v\nthresholds: %v\n", psp, pst)
	return pubsub.WithPeerScore(&psp, &pst)
}

func convertTopicParams(p *TopicScoreParams) *pubsub.TopicScoreParams {
	return &pubsub.TopicScoreParams{
		TopicWeight:                     p.TopicWeight,
		TimeInMeshWeight:                p.TimeInMeshWeight,
		TimeInMeshQuantum:               p.TimeInMeshQuantum.Duration,
		TimeInMeshCap:                   p.TimeInMeshCap,
		FirstMessageDeliveriesWeight:    p.FirstMessageDeliveriesWeight,
		FirstMessageDeliveriesDecay:     p.FirstMessageDeliveriesDecay,
		FirstMessageDeliveriesCap:       p.FirstMessageDeliveriesCap,
		MeshMessageDeliveriesWeight:     p.MeshMessageDeliveriesWeight,
		MeshMessageDeliveriesDecay:      p.MeshMessageDeliveriesDecay,
		MeshMessageDeliveriesCap:        p.MeshMessageDeliveriesCap,
		MeshMessageDeliveriesThreshold:  p.MeshMessageDeliveriesThreshold,
		MeshMessageDeliveriesWindow:     p.MeshMessageDeliveriesWindow.Duration,
		MeshMessageDeliveriesActivation: p.MeshMessageDeliveriesActivation.Duration,
		MeshFailurePenaltyWeight:        p.MeshFailurePenaltyWeight,
		MeshFailurePenaltyDecay:         p.MeshFailurePenaltyDecay,
		InvalidMessageDeliveriesWeight:  p.InvalidMessageDeliveriesWeight,
		InvalidMessageDeliveriesDecay:   p.InvalidMessageDeliveriesDecay,
	}
}
