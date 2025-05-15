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
    # Action to run if the NodeID is equal to the above value
    action: ScriptAction


class WaitUntil(BaseModel):
    """
    Implementations MUST wait until elapsedSeconds is greater than or equal to the specified value.
    They MUST NOT execute any proceeding actions until the wait is complete.
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

ScriptAction = Union[Connect, IfNodeIDEquals, WaitUntil, Publish, SubscribeToTopic]
