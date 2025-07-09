from __future__ import annotations

from typing import List, Literal, Optional, TypeAlias, Union
from pydantic import BaseModel, Field

NodeID: TypeAlias = int


class Connect(BaseModel):
    type: Literal["connect"] = "connect"
    connectTo: List[NodeID]


class IfNodeIDEquals(BaseModel):
    type: Literal["ifNodeIDEquals"] = "ifNodeIDEquals"
    nodeID: NodeID
    # Instruction to run if the NodeID is equal to the above value
    instruction: "ScriptInstruction"


class WaitUntil(BaseModel):
    """
    Implementations MUST wait until elapsedSeconds is greater than or equal to the specified value.
    They MUST NOT execute any proceeding instruction until the wait is complete.
    They MUST still handle message delivery and forwarding as normal.
    """

    type: Literal["waitUntil"] = "waitUntil"
    elapsedSeconds: int  # Seconds elapsed since test start


class Publish(BaseModel):
    type: Literal["publish"] = "publish"
    messageID: int
    messageSizeBytes: int
    topicID: str


class SubscribeToTopic(BaseModel):
    type: Literal["subscribeToTopic"] = "subscribeToTopic"
    topicID: str


class SetTopicValidationDelay(BaseModel):
    """
    SetTopicValidationDelay is an instruction that lets us mock some
    validation process by delaying the validation results by some number of
    seconds.
    """
    type: Literal["setTopicValidationDelay"] = "setTopicValidationDelay"
    topicID: str
    delaySeconds: float


class InitGossipSub(BaseModel):
    """
    InitGossipSub is an instruction that initializes the GossipSub protocol with the
    given parameters.

    It is undefined behavior to not have every node InitGossipSub before any other instruction.
    """

    type: Literal["initGossipSub"] = "initGossipSub"
    gossipSubParams: "GossipSubParams"


class GossipSubParams(BaseModel):
    # Overlay parameters
    D: Optional[int] = None  # Optimal degree for a GossipSub topic mesh
    Dlo: Optional[int] = None  # Lower bound on the number of peers in a topic mesh
    Dhi: Optional[int] = None  # Upper bound on the number of peers in a topic mesh
    Dscore: Optional[int] = None  # Number of high-scoring peers to retain when pruning
    Dout: Optional[int] = None  # Quota for outbound connections to maintain in a topic mesh
    DRobust: Optional[int] = Field(default=None, alias="d-robust") # D robust value for WFR gossipsub

    # Gossip parameters
    HistoryLength: Optional[int] = None  # Size of the message cache used for gossip
    HistoryGossip: Optional[int] = None  # Number of cached message IDs to advertise in IHAVE
    Dlazy: Optional[int] = None  # Minimum number of peers to emit gossip to at each heartbeat

    # Factor affecting how many peers receive gossip
    GossipFactor: Optional[float] = None
    GossipRetransmission: Optional[int] = None  # Limit for IWANT requests before ignoring a peer

    # Heartbeat parameters
    HeartbeatInitialDelay: Optional[float] = None  # Initial delay in seconds before heartbeat timer begins
    HeartbeatInterval: Optional[int] = None  # Time between heartbeats in seconds
    SlowHeartbeatWarning: Optional[float] = None  # Threshold for heartbeat processing warnings

    # Fanout and pruning
    FanoutTTL: Optional[int] = None  # Time in seconds to track fanout state
    PrunePeers: Optional[int] = None  # Number of peers to include in prune Peer eXchange
    PruneBackoff: Optional[int] = None  # Backoff time in seconds for pruned peers
    # Backoff time in seconds after unsubscribing
    UnsubscribeBackoff: Optional[int] = None

    # Connection management
    Connectors: Optional[int] = None  # Number of active connection attempts for PX peers
    MaxPendingConnections: Optional[int] = None # Maximum number of pending connections
    ConnectionTimeout: Optional[int] = None # Timeout in seconds for connection attempts
    DirectConnectTicks: Optional[int] = None  # Heartbeat ticks for reconnecting direct peers
    DirectConnectInitialDelay: Optional[int] = None  # Initial delay before connecting to direct peers

    # Opportunistic grafting
    OpportunisticGraftTicks: Optional[int] = None  # Ticks between opportunistic grafting attempts
    OpportunisticGraftPeers: Optional[int] = None  # Number of peers to opportunistically graft
    GraftFloodThreshold: Optional[int] = None  # Time threshold in seconds for GRAFT flood detection

    # Message control
    MaxIHaveLength: Optional[int] = None  # Maximum messages in an IHAVE message
    MaxIHaveMessages: Optional[int] = None  # Maximum IHAVE messages to accept per heartbeat
    MaxIDontWantLength: Optional[int] = None # Maximum messages in an IDONTWANT message
    MaxIDontWantMessages: Optional[int] = None  # Maximum IDONTWANT messages to accept per heartbeat
    IWantFollowupTime: Optional[int] = None # Time in seconds to wait for IWANT followup
    IDontWantMessageThreshold: Optional[int] = None  # Size threshold for IDONTWANT messages
    IDontWantMessageTTL: Optional[int] = None  # TTL in seconds for IDONTWANT messages


ScriptInstruction = Union[
    Connect, IfNodeIDEquals, WaitUntil, Publish, SubscribeToTopic,
    SetTopicValidationDelay, InitGossipSub
]

# Rebuild the models to resolve forward references like "ScriptInstruction"
IfNodeIDEquals.model_rebuild()
InitGossipSub.model_rebuild()
