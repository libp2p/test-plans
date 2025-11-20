import socket
import trio
from abc import ABCMeta, abstractmethod
from typing import List, Tuple, Union, Any, Optional, Generic, TypeVar, AsyncIterator
from types import TracebackType

_T = TypeVar("_T")

class Clock(metaclass=ABCMeta):
    @abstractmethod
    def start_clock(self) -> None: ...
    @abstractmethod
    def current_time(self) -> float: ...
    @abstractmethod
    def deadline_to_sleep_time(self, deadline: float) -> float: ...

class Instrument(metaclass=ABCMeta):
    def before_run(self) -> None: ...
    def after_run(self) -> None: ...
    def task_spawned(self, task: trio.lowlevel.Task) -> None: ...
    def task_scheduled(self, task: trio.lowlevel.Task) -> None: ...
    def before_task_step(self, task: trio.lowlevel.Task) -> None: ...
    def after_task_step(self, task: trio.lowlevel.Task) -> None: ...
    def task_exited(self, task: trio.lowlevel.Task) -> None: ...
    def before_io_wait(self, timeout: float) -> None: ...
    def after_io_wait(self, timeout: float) -> None: ...

class HostnameResolver(metaclass=ABCMeta):
    @abstractmethod
    async def getaddrinfo(
        self,
        host: bytes,
        port: Union[str, int, None],
        family: int = ...,
        type: int = ...,
        proto: int = ...,
        flags: int = ...,
    ) -> List[Tuple[int, int, int, str, Tuple[Any, ...]]]: ...
    @abstractmethod
    async def getnameinfo(
        self, sockaddr: Tuple[Any, ...], flags: int
    ) -> Tuple[str, str]: ...

class SocketFactory(metaclass=ABCMeta):
    @abstractmethod
    def socket(
        self,
        family: socket.AddressFamily | int = ...,
        type: socket.SocketKind | int = ...,
        proto: int = ...,
    ) -> trio.socket.SocketType: ...

class AsyncResource(metaclass=ABCMeta):
    @abstractmethod
    async def aclose(self) -> None: ...
    async def __aenter__(self: _T) -> _T: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

class SendStream(AsyncResource):
    @abstractmethod
    async def send_all(self, data: Union[bytes, memoryview]) -> None: ...
    @abstractmethod
    async def wait_send_all_might_not_block(self) -> None: ...

class ReceiveStream(AsyncResource):
    @abstractmethod
    async def receive_some(self, max_bytes: Optional[int] = ...) -> bytes: ...
    def __aiter__(self) -> AsyncIterator[bytes]: ...
    async def __anext__(self) -> bytes: ...

class Stream(SendStream, ReceiveStream, metaclass=ABCMeta):
    pass

class HalfCloseableStream(Stream):
    @abstractmethod
    async def send_eof(self) -> None: ...

_SomeResource = TypeVar("_SomeResource", bound=AsyncResource, covariant=True)

class Listener(AsyncResource, Generic[_SomeResource]):
    @abstractmethod
    async def accept(self) -> _SomeResource: ...

_T1 = TypeVar("_T1")

_T_co = TypeVar("_T_co", covariant=True)
_T_contra = TypeVar("_T_contra", contravariant=True)

class SendChannel(AsyncResource, Generic[_T_contra]):
    @abstractmethod
    async def send(self, value: _T_contra) -> None: ...

class ReceiveChannel(AsyncResource, Generic[_T_co]):
    @abstractmethod
    async def receive(self) -> _T_co: ...
    def __aiter__(self) -> AsyncIterator[_T_co]: ...
    async def __anext__(self) -> _T_co: ...

class Channel(SendChannel[_T], ReceiveChannel[_T], metaclass=ABCMeta):
    pass
