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
