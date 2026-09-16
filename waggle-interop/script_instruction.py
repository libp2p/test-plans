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


class AddPiece(BaseModel):
    type: Literal["addPiece"] = "addPiece"
    parts: int  # uint8 representing bitmap
    topicID: str
    objectID: int  # uint64 representing objectID


class Publish(BaseModel):
    type: Literal["publish"] = "publish"
    topicID: str
    objectID: int  # uint64 representing objectID


class SubscribeToTopic(BaseModel):
    type: Literal["subscribeToTopic"] = "subscribeToTopic"
    topicID: str


class InitWaggle(BaseModel):
    """
    InitWaggle is an instruction that initializes the Waggle protocol with the
    given parameters.

    It is undefined behavior to not have every node InitWaggle before any other instruction.
    """

    type: Literal["initWaggle"] = "initWaggle"
    waggleParams: WaggleParams


class WaggleParams(BaseModel):
    publishFanout: int | None = (
        None  # Number of connected peers to randomly select when publishing a new piece
    )
    gossipFanout: int | None = (
        None  # Number of connected peers to gossip metadata to upon receiving a new piece
    )


ScriptInstruction = Union[
    Connect,
    IfNodeIDEquals,
    WaitUntil,
    SubscribeToTopic,
    InitWaggle,
    AddPiece,
    Publish,
]
