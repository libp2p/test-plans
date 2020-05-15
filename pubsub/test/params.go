package main

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/testground/sdk-go/ptypes"
	"github.com/testground/sdk-go/runtime"
)

type NodeType string

const (
	NodeTypeHonest NodeType = "honest"
)

type TopicConfig struct {
	Id          string      `json:"id"`
	MessageRate ptypes.Rate `json:"message_rate"`
	MessageSize ptypes.Size `json:"message_size"`
}

type HeartbeatParams struct {
	InitialDelay time.Duration
	Interval     time.Duration
}

type NetworkParams struct {
	latency     time.Duration
	latencyMax  time.Duration
	jitterPct   int
	bandwidthMB int
}

// ScoreParams is mapped to pubsub.PeerScoreParams when targeting the hardened_api pubsub branch
type ScoreParams struct {
	Topics     map[string]*TopicScoreParams
	Thresholds PeerScoreThresholds

	// TODO: figure out how to parameterize the app score function

	IPColocationFactorWeight    float64
	IPColocationFactorThreshold int

	DecayInterval ptypes.Duration
	DecayToZero   float64
	RetainScore   ptypes.Duration
}

type OverlayParams struct {
	d            int
	dlo          int
	dhi          int
	dscore       int
	dlazy        int
	gossipFactor float64
}

type PeerScoreThresholds struct {
	GossipThreshold             float64
	PublishThreshold            float64
	GraylistThreshold           float64
	AcceptPXThreshold           float64
	OpportunisticGraftThreshold float64
}

// TopicScoreParams is mapped to pubsub.TopicScoreParams when targeting the hardened_api pubsub branch
type TopicScoreParams struct {
	TopicWeight float64

	TimeInMeshWeight  float64
	TimeInMeshQuantum ptypes.Duration
	TimeInMeshCap     float64

	FirstMessageDeliveriesWeight float64
	FirstMessageDeliveriesDecay  float64
	FirstMessageDeliveriesCap    float64

	MeshMessageDeliveriesWeight, MeshMessageDeliveriesDecay      float64
	MeshMessageDeliveriesCap, MeshMessageDeliveriesThreshold     float64
	MeshMessageDeliveriesWindow, MeshMessageDeliveriesActivation ptypes.Duration

	MeshFailurePenaltyWeight, MeshFailurePenaltyDecay float64

	InvalidMessageDeliveriesWeight, InvalidMessageDeliveriesDecay float64
}


type testParams struct {
	heartbeat HeartbeatParams
	setup     time.Duration
	warmup    time.Duration
	runtime   time.Duration
	cooldown  time.Duration

	nodeType        NodeType
	publisher       bool
	floodPublishing bool
	fullTraces      bool
	topics          []TopicConfig
	degree          int

	containerNodesTotal int
	nodesPerContainer   int

	connectDelays           []time.Duration
	connectDelayJitterPct   int
	connsDef                map[string]*ConnectionsDef
	connectToPublishersOnly bool

	netParams          NetworkParams
	overlayParams      OverlayParams
	scoreParams        ScoreParams
	scoreInspectPeriod time.Duration
	validateQueueSize  int
	outboundQueueSize  int

	opportunisticGraftTicks int
}

func durationParam(runenv *runtime.RunEnv, name string) time.Duration {
	if !runenv.IsParamSet(name) {
		runenv.RecordMessage("duration param %s not set, defaulting to zero", name)
		return 0
	}
	return parseDuration(runenv.StringParam(name))
}

func parseDuration(val string) time.Duration {
	d, err := time.ParseDuration(val)
	if err != nil {
		panic(fmt.Errorf("param %s is not a valid duration: %s", val, err))
	}
	return d
}

func parseParams(runenv *runtime.RunEnv) testParams {
	np := NetworkParams{
		latency:     durationParam(runenv, "t_latency"),
		latencyMax:  durationParam(runenv, "t_latency_max"),
		jitterPct:   runenv.IntParam("jitter_pct"),
		bandwidthMB: runenv.IntParam("bandwidth_mb"),
	}

	op := OverlayParams{
		d:            runenv.IntParam("overlay_d"),
		dlo:          runenv.IntParam("overlay_dlo"),
		dhi:          runenv.IntParam("overlay_dhi"),
		dscore:       runenv.IntParam("overlay_dscore"),
		dlazy:        runenv.IntParam("overlay_dlazy"),
		gossipFactor: runenv.FloatParam("gossip_factor"),
	}

	p := testParams{
		heartbeat: HeartbeatParams{
			InitialDelay: durationParam(runenv, "t_heartbeat_initial_delay"),
			Interval:     durationParam(runenv, "t_heartbeat"),
		},
		setup:                   durationParam(runenv, "t_setup"),
		warmup:                  durationParam(runenv, "t_warm"),
		runtime:                 durationParam(runenv, "t_run"),
		cooldown:                durationParam(runenv, "t_cool"),
		publisher:               runenv.BooleanParam("publisher"),
		floodPublishing:         runenv.BooleanParam("flood_publishing"),
		fullTraces:              runenv.BooleanParam("full_traces"),
		nodeType:                NodeTypeHonest,
		connectToPublishersOnly: runenv.BooleanParam("connect_to_publishers_only"),
		degree:                  runenv.IntParam("degree"),
		containerNodesTotal:     runenv.IntParam("n_container_nodes_total"),
		nodesPerContainer:       runenv.IntParam("n_nodes_per_container"),
		scoreInspectPeriod:      durationParam(runenv, "t_score_inspect_period"),
		netParams:               np,
		overlayParams:           op,
		validateQueueSize:       runenv.IntParam("validate_queue_size"),
		outboundQueueSize:       runenv.IntParam("outbound_queue_size"),
		opportunisticGraftTicks: runenv.IntParam("opportunistic_graft_ticks"),
	}

	if runenv.IsParamSet("topics") {
		jsonstr := runenv.StringParam("topics")
		err := json.Unmarshal([]byte(jsonstr), &p.topics)
		if err != nil {
			panic(err)
		}
		runenv.RecordMessage("topics: %v", p.topics)
	}

	if runenv.IsParamSet("score_params") {
		jsonstr := runenv.StringParam("score_params")
		err := json.Unmarshal([]byte(jsonstr), &p.scoreParams)
		if err != nil {
			panic(err)
		}

		// add warmup time to the mesh delivery activation window for each topic
		for _, topic := range p.scoreParams.Topics {
			topic.MeshMessageDeliveriesActivation.Duration += p.warmup
		}
	}

	if runenv.IsParamSet("topology") {
		jsonstr := runenv.StringParam("topology")
		err := json.Unmarshal([]byte(jsonstr), &p.connsDef)
		if err != nil {
			panic(err)
		}
	}

	if runenv.IsParamSet("connect_delays") {
		// eg: "5@10s,15@1m,5@2m"
		connDelays := runenv.StringParam("connect_delays")
		if connDelays != "" && connDelays != "\"\"" {
			cds := strings.Split(connDelays, ",")
			for _, cd := range cds {
				parts := strings.Split(cd, "@")
				if len(parts) != 2 {
					panic(fmt.Sprintf("Badly formatted connect_delays param %s", connDelays))
				}
				count, err := strconv.Atoi(parts[0])
				if err != nil {
					panic(fmt.Sprintf("Badly formatted connect_delays param %s", connDelays))
				}

				dur := parseDuration(parts[1])
				for i := 0; i < count; i++ {
					p.connectDelays = append(p.connectDelays, dur)
				}
			}
		}

		p.connectDelayJitterPct = 5
		if runenv.IsParamSet("connect_delay_jitter_pct") {
			p.connectDelayJitterPct = runenv.IntParam("connect_delay_jitter_pct")
		}
	}

	return p
}

func parseNodeType(nt string) NodeType {
	switch nt {
	// currently only honest nodes are supported
	default:
		return NodeTypeHonest
	}
}
