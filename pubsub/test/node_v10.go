// This file is used when the hardened_api build tag is not present.
// It targets the go-libp2p-pubsub API before GossipSub v1.1.0 was introduced.
// When using this file, peer scores will not be present in the test output.

package main

import (
	pubsub "github.com/libp2p/go-libp2p-pubsub"
)

func pubsubOptions(cfg PubsubNodeConfig) ([]pubsub.Option, error) {
	opts := []pubsub.Option{
		pubsub.WithEventTracer(cfg.Tracer),
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

	return opts, nil
}
