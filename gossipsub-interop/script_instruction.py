from __future__ import annotations

from typing import List, Literal, TypeAlias, Union
from pydantic import BaseModel

NodeID: TypeAlias = int


class Connect(BaseModel):
    type: Literal["connect"] = "connect"
    connectTo: List[NodeID]


class IfNodeIDEquals(BaseModel):
    type: Literal["ifNodeIDEquals"] = "ifNodeIDEquals"
    nodeID: NodeID
    # Instruction to run if the NodeID is equal to the above value
    instruction: ScriptInstruction


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


class InitGossipSub(BaseModel):
    """
    InitGossipSub is an instruction that initializes the GossipSub protocol with the
    given parameters.

    It is undefined behavior to not have every node InitGossipSub before any other instruction.
    """

    type: Literal["initGossipSub"] = "initGossipSub"
    gossipSubParams: GossipSubParams


class GossipSubParams(BaseModel):
    # Overlay parameters
    D: int | None = None  # Optimal degree for a GossipSub topic mesh
    Dlo: int | None = None  # Lower bound on the number of peers in a topic mesh
    Dhi: int | None = None  # Upper bound on the number of peers in a topic mesh
    Dscore: int | None = None  # Number of high-scoring peers to retain when pruning
    Dout: int | None = (
        None  # Quota for outbound connections to maintain in a topic mesh
    )

    # Gossip parameters
    HistoryLength: int | None = None  # Size of the message cache used for gossip
    HistoryGossip: int | None = (
        None  # Number of cached message IDs to advertise in IHAVE
    )
    Dlazy: int | None = (
        None  # Minimum number of peers to emit gossip to at each heartbeat
    )
    GossipFactor: float | None = None  # Factor affecting how many peers receive gossip
    GossipRetransmission: int | None = (
        None  # Limit for IWANT requests before ignoring a peer
    )

    # Heartbeat parameters
    HeartbeatInitialDelay: int | None = (
        None  # Initial delay in seconds before heartbeat timer begins
    )
    HeartbeatInterval: int | None = None  # Time between heartbeats in seconds
    SlowHeartbeatWarning: float | None = (
        None  # Threshold for heartbeat processing warnings
    )

    # Fanout and pruning
    FanoutTTL: int | None = None  # Time in seconds to track fanout state
    PrunePeers: int | None = None  # Number of peers to include in prune Peer eXchange
    PruneBackoff: int | None = None  # Backoff time in seconds for pruned peers
    UnsubscribeBackoff: int | None = None  # Backoff time in seconds after unsubscribing

    # Connection management
    Connectors: int | None = None  # Number of active connection attempts for PX peers
    MaxPendingConnections: int | None = None  # Maximum number of pending connections
    ConnectionTimeout: int | None = None  # Timeout in seconds for connection attempts
    DirectConnectTicks: int | None = (
        None  # Heartbeat ticks for reconnecting direct peers
    )
    DirectConnectInitialDelay: int | None = (
        None  # Initial delay before connecting to direct peers
    )

    # Opportunistic grafting
    OpportunisticGraftTicks: int | None = (
        None  # Ticks between opportunistic grafting attempts
    )
    OpportunisticGraftPeers: int | None = (
        None  # Number of peers to opportunistically graft
    )
    GraftFloodThreshold: int | None = (
        None  # Time threshold in seconds for GRAFT flood detection
    )

    # Message control
    MaxIHaveLength: int | None = None  # Maximum messages in an IHAVE message
    MaxIHaveMessages: int | None = (
        None  # Maximum IHAVE messages to accept per heartbeat
    )
    MaxIDontWantLength: int | None = None  # Maximum messages in an IDONTWANT message
    MaxIDontWantMessages: int | None = (
        None  # Maximum IDONTWANT messages to accept per heartbeat
    )
    IWantFollowupTime: int | None = None  # Time in seconds to wait for IWANT followup
    IDontWantMessageThreshold: int | None = (
        None  # Size threshold for IDONTWANT messages
    )
    IDontWantMessageTTL: int | None = None  # TTL in seconds for IDONTWANT messages


ScriptInstruction = Union[
    Connect, IfNodeIDEquals, WaitUntil, Publish, SubscribeToTopic, InitGossipSub
]
