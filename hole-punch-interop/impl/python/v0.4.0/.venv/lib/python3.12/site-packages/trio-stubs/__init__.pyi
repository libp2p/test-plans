from abc import ABCMeta
from typing import (
    Any,
    AnyStr,
    AsyncContextManager,
    AsyncIterator,
    Awaitable,
    Callable,
    ContextManager,
    FrozenSet,
    Generic,
    Iterator,
    Mapping,
    NoReturn,
    Optional,
    Union,
    Sequence,
    TypeVar,
    Tuple,
    List,
    Iterable,
    TextIO,
    BinaryIO,
    IO,
    overload,
    final,
)
from types import TracebackType

from _typeshed import StrOrBytesPath
from _typeshed import OpenBinaryMode, OpenTextMode, ReadableBuffer, WriteableBuffer
from trio_typing import TaskStatus, takes_callable_and_args
from typing_extensions import Protocol, Literal, Buffer
from mypy_extensions import NamedArg, VarArg
import signal
import io
import os
import pathlib
import subprocess
import ssl
import sys
import trio
import attr
from . import lowlevel as lowlevel, socket as socket, abc as abc
from . import to_thread as to_thread, from_thread as from_thread

_T = TypeVar("_T")
_T_co = TypeVar("_T_co", covariant=True)
_T_contra = TypeVar("_T_contra", contravariant=True)

# Inheriting from this (even outside of stubs) produces a class that
# mypy thinks is abstract, but the interpreter thinks is concrete.
class _NotConstructible(Protocol):
    _objects_of_this_type_are_not_directly_constructible: None

# _core._exceptions
class TrioInternalError(Exception):
    pass

class RunFinishedError(Exception):
    pass

class WouldBlock(Exception):
    pass

class BusyResourceError(Exception):
    pass

class ClosedResourceError(Exception):
    pass

class BrokenResourceError(Exception):
    pass

class EndOfChannel(Exception):
    pass

class NoHandshakeError(Exception):
    pass

@final
class Cancelled(BaseException, _NotConstructible, metaclass=ABCMeta):
    pass

# _core._multierror
class MultiError(BaseException):
    @property
    def exceptions(self) -> List[BaseException]:
        pass
    def __init__(
        self, exceptions: Sequence[BaseException], *, _collapse: bool = ...
    ): ...
    def __new__(
        cls: _T, exceptions: Sequence[BaseException], *, _collapse: bool = ...
    ) -> _T: ...
    @classmethod
    def filter(
        cls,
        handler: Callable[[BaseException], Optional[BaseException]],
        root_exc: BaseException,
    ) -> BaseException: ...
    @classmethod
    def catch(
        cls, handler: Callable[[BaseException], Optional[BaseException]]
    ) -> ContextManager[None]: ...

# _core._run
TASK_STATUS_IGNORED: TaskStatus[Any]

@final
@attr.s(eq=False, repr=False, slots=True, auto_attribs=False)
class CancelScope(metaclass=ABCMeta):
    deadline: float = attr.ib(default=None, kw_only=True)
    shield: bool = attr.ib(default=None, kw_only=True)
    @property
    def cancel_called(self) -> bool: ...
    cancelled_caught: bool
    def __enter__(self) -> CancelScope: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> bool | None: ...
    def cancel(self) -> None: ...

@final
@attr.s(eq=False, repr=False, slots=True)
class Nursery(_NotConstructible, metaclass=ABCMeta):
    cancel_scope: CancelScope
    @property
    def child_tasks(self) -> FrozenSet[trio.lowlevel.Task]: ...
    @property
    def parent_task(self) -> trio.lowlevel.Task: ...
    @takes_callable_and_args
    def start_soon(
        self,
        async_fn: Union[
            # List these explicitly instead of Callable[..., Awaitable[Any]]
            # so that even without the plugin we catch cases of passing a
            # function with keyword-only arguments to start_soon().
            Callable[[], Awaitable[Any]],
            Callable[[Any], Awaitable[Any]],
            Callable[[Any, Any], Awaitable[Any]],
            Callable[[Any, Any, Any], Awaitable[Any]],
            Callable[[Any, Any, Any, Any], Awaitable[Any]],
            Callable[[VarArg()], Awaitable[Any]],
        ],
        *args: Any,
        name: object = None,
    ) -> None: ...
    @takes_callable_and_args
    async def start(
        self,
        async_fn: Union[
            # List these explicitly instead of Callable[..., Awaitable[Any]]
            # so that even without the plugin we can infer the return type
            # of start(), and fail when a function is passed that doesn't
            # accept task_status.
            Callable[[NamedArg(TaskStatus[_T], "task_status")], Awaitable[Any]],
            Callable[[Any, NamedArg(TaskStatus[_T], "task_status")], Awaitable[Any]],
            Callable[
                [Any, Any, NamedArg(TaskStatus[_T], "task_status")], Awaitable[Any]
            ],
            Callable[
                [Any, Any, Any, NamedArg(TaskStatus[_T], "task_status")], Awaitable[Any]
            ],
            Callable[
                [Any, Any, Any, Any, NamedArg(TaskStatus[_T], "task_status")],
                Awaitable[Any],
            ],
            Callable[
                [VarArg(), NamedArg(TaskStatus[_T], "task_status")], Awaitable[Any]
            ],
        ],
        *args: Any,
        name: object = None,
    ) -> _T: ...

def open_nursery(
    strict_exception_groups: bool | None = ...,
) -> AsyncContextManager[Nursery]: ...
def current_effective_deadline() -> float: ...
def current_time() -> float: ...
@takes_callable_and_args
def run(
    afn: Union[Callable[..., Awaitable[_T]], Callable[[VarArg()], Awaitable[_T]]],
    *args: Any,
    clock: Optional[trio.abc.Clock] = ...,
    instruments: Sequence[trio.abc.Instrument] = ...,
    restrict_keyboard_interrupt_to_checkpoints: bool = ...,
    strict_exception_groups: bool = ...,
) -> _T: ...

# _timeouts
def move_on_at(deadline: float) -> CancelScope: ...
def move_on_after(seconds: float) -> CancelScope: ...
async def sleep_forever() -> NoReturn: ...
async def sleep_until(deadline: float) -> None: ...
async def sleep(seconds: float) -> None: ...
def fail_at(deadline: float) -> ContextManager[CancelScope]: ...
def fail_after(seconds: float) -> ContextManager[CancelScope]: ...

class TooSlowError(Exception):
    pass

# _sync
@attr.s(frozen=True, slots=True)
class EventStatistics:
    tasks_waiting: int = attr.ib()

@final
@attr.s(eq=False, repr=False, slots=True)
class Event(metaclass=ABCMeta):
    def is_set(self) -> bool: ...
    def set(self) -> None: ...
    async def wait(self) -> None: ...
    def statistics(self) -> EventStatistics: ...

@attr.s(frozen=True, slots=True)
class CapacityLimiterStatistics:
    borrowed_tokens: int = attr.ib()
    total_tokens: int | float = attr.ib()
    borrowers: list[trio.lowlevel.Task | object] = attr.ib()
    tasks_waiting: int = attr.ib()

@final
class CapacityLimiter(metaclass=ABCMeta):
    # float here really means Union[int, math.inf] but mypy doesn't
    # understand that
    total_tokens: float
    @property
    def borrowed_tokens(self) -> int: ...
    @property
    def available_tokens(self) -> float: ...
    def __init__(self, total_tokens: float): ...
    def acquire_nowait(self) -> None: ...
    def acquire_on_behalf_of_nowait(self, borrower: object) -> None: ...
    async def acquire(self) -> None: ...
    async def acquire_on_behalf_of(self, borrower: object) -> None: ...
    def release(self) -> None: ...
    def release_on_behalf_of(self, borrower: object) -> None: ...
    def statistics(self) -> CapacityLimiterStatistics: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

@final
class Semaphore(metaclass=ABCMeta):
    @property
    def value(self) -> int: ...
    @property
    def max_value(self) -> Optional[int]: ...
    def __init__(self, initial_value: int, *, max_value: Optional[int] = None): ...
    def acquire_nowait(self) -> None: ...
    async def acquire(self) -> None: ...
    def release(self) -> None: ...
    def statistics(self) -> lowlevel.ParkingLotStatistics: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

@attr.s(frozen=True, slots=True)
class LockStatistics:
    locked: bool = attr.ib()
    owner: trio.lowlevel.Task | None = attr.ib()
    tasks_waiting: int = attr.ib()

@final
class Lock(metaclass=ABCMeta):
    def locked(self) -> bool: ...
    def acquire_nowait(self) -> None: ...
    async def acquire(self) -> None: ...
    def release(self) -> None: ...
    def statistics(self) -> LockStatistics: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

@final
class StrictFIFOLock(metaclass=ABCMeta):
    def locked(self) -> bool: ...
    def acquire_nowait(self) -> None: ...
    async def acquire(self) -> None: ...
    def release(self) -> None: ...
    def statistics(self) -> LockStatistics: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

@attr.s(frozen=True, slots=True)
class ConditionStatistics:
    tasks_waiting: int = attr.ib()
    lock_statistics: LockStatistics = attr.ib()

@final
class Condition(metaclass=ABCMeta):
    def __init__(self, lock: Optional[Union[Lock, StrictFIFOLock]] = None) -> None: ...
    def locked(self) -> bool: ...
    def acquire_nowait(self) -> None: ...
    async def acquire(self) -> None: ...
    def release(self) -> None: ...
    async def wait(self) -> None: ...
    def notify(self, n: int = 1) -> None: ...
    def notify_all(self) -> None: ...
    def statistics(self) -> ConditionStatistics: ...
    async def __aenter__(self) -> None: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

# _highlevel_generic
async def aclose_forcefully(resource: trio.abc.AsyncResource) -> None: ...
@final
@attr.s(eq=False, hash=False)
class StapledStream(trio.abc.HalfCloseableStream):
    send_stream: trio.abc.SendStream = attr.ib()
    receive_stream: trio.abc.ReceiveStream = attr.ib()
    async def aclose(self) -> None: ...
    async def send_all(self, data: Union[bytes, memoryview]) -> None: ...
    async def wait_send_all_might_not_block(self) -> None: ...
    async def receive_some(self, max_bytes: Optional[int] = ...) -> bytes: ...
    async def send_eof(self) -> None: ...

# _channel
@attr.s(frozen=True, slots=True)
class _MemoryChannelStats:
    current_buffer_used: int = attr.ib()
    max_buffer_size: int | float = attr.ib()
    open_send_channels: int = attr.ib()
    open_receive_channels: int = attr.ib()
    tasks_waiting_send: int = attr.ib()
    tasks_waiting_receive: int = attr.ib()

@final
@attr.s(eq=False, repr=False)
class MemorySendChannel(trio.abc.SendChannel[_T_contra]):
    def send_nowait(self, value: _T_contra) -> None: ...
    async def send(self, value: _T_contra) -> None: ...
    def clone(self: _T) -> _T: ...
    async def aclose(self) -> None: ...
    def statistics(self) -> _MemoryChannelStats: ...
    def close(self) -> None: ...
    def __enter__(self) -> MemorySendChannel[_T_contra]: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None: ...

@final
@attr.s(eq=False, repr=False)
class MemoryReceiveChannel(trio.abc.ReceiveChannel[_T_co]):
    def receive_nowait(self) -> _T_co: ...
    async def receive(self) -> _T_co: ...
    def clone(self: _T) -> _T: ...
    async def aclose(self) -> None: ...
    def statistics(self) -> _MemoryChannelStats: ...
    def close(self) -> None: ...
    def __enter__(self) -> MemoryReceiveChannel[_T_co]: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None: ...

# written as a class so you can say open_memory_channel[int](5)
class open_memory_channel(Tuple[MemorySendChannel[_T], MemoryReceiveChannel[_T]]):
    def __new__(  # type: ignore[misc]  # "must return a subtype"
        cls, max_buffer_size: float
    ) -> Tuple[MemorySendChannel[_T], MemoryReceiveChannel[_T]]: ...
    def __init__(self, max_buffer_size: float): ...

# _signals
def open_signal_receiver(
    *signals: signal.Signals,
) -> ContextManager[AsyncIterator[int]]: ...

# _highlevel_socket
@final
class SocketStream(trio.abc.HalfCloseableStream):
    socket: trio.socket.SocketType
    def __init__(self, socket: trio.socket.SocketType) -> None: ...
    @overload
    def setsockopt(
        self, level: int, option: int, value: int | Buffer, length: None = None
    ) -> None: ...
    @overload
    def setsockopt(self, level: int, option: int, value: None, length: int) -> None: ...
    @overload
    def getsockopt(self, level: int, option: int) -> int: ...
    @overload
    def getsockopt(self, level: int, option: int, buffersize: int) -> bytes: ...
    async def aclose(self) -> None: ...
    async def send_all(self, data: Union[bytes, memoryview]) -> None: ...
    async def wait_send_all_might_not_block(self) -> None: ...
    async def receive_some(self, max_bytes: Optional[int] = ...) -> bytes: ...
    async def send_eof(self) -> None: ...

@final
class SocketListener(trio.abc.Listener[SocketStream]):
    socket: trio.socket.SocketType
    def __init__(self, socket: trio.socket.SocketType) -> None: ...
    async def accept(self) -> SocketStream: ...
    async def aclose(self) -> None: ...

# _dtls
@final
class DTLSEndpoint(metaclass=ABCMeta):
    socket: trio.socket.SocketType
    incoming_packets_buffer: int
    def __init__(
        self, socket: trio.socket.SocketType, *, incoming_packets_buffer: int = ...
    ) -> None: ...
    # ssl_context is an OpenSSL.SSL.Context from PyOpenSSL, but we can't
    # import that name because we don't depend on PyOpenSSL
    def connect(
        self, address: Union[Tuple[Any, ...], str, bytes], ssl_context: Any
    ) -> DTLSChannel: ...
    @takes_callable_and_args
    async def serve(
        self,
        ssl_context: Any,
        async_fn: Union[
            Callable[..., Awaitable[Any]],
            Callable[[DTLSChannel, VarArg()], Awaitable[Any]],
        ],
        *args: Any,
        task_status: TaskStatus[None] = ...,
    ) -> NoReturn: ...
    def close(self) -> None: ...
    def __enter__(self) -> DTLSEndpoint: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None: ...

@attr.frozen
class DTLSChannelStatistics:
    incoming_packets_dropped_in_trio: int

@final
class DTLSChannel(_NotConstructible, trio.abc.Channel[bytes], metaclass=ABCMeta):
    endpoint: DTLSEndpoint
    peer_address: Union[Tuple[Any, ...], str, bytes]
    async def do_handshake(
        self, *, initial_retransmit_timeout: float = ...
    ) -> None: ...
    async def send(self, data: bytes) -> None: ...
    async def receive(self) -> bytes: ...
    def set_ciphertext_mtu(self, new_mtu: int) -> None: ...
    def get_cleartext_mtu(self) -> int: ...
    def statistics(self) -> DTLSChannelStatistics: ...
    async def aclose(self) -> None: ...
    def close(self) -> None: ...
    def __enter__(self) -> DTLSChannel: ...
    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None: ...

# _file_io

# The actual Trio I/O classes use metaprogramming to forward their methods
# to a regular non-async underlying I/O object. We represent this by replicating
# the I/O type hierarchy (ABCs from typing.pyi and implementations from io.pyi)
# with additional 'async' on the necessary methods.

# ABCs: (from typing.pyi, with more async)
class AsyncIO(AsyncIterator[AnyStr], Generic[AnyStr], trio.abc.AsyncResource):
    mode: str
    name: Union[str, int]  # whatever was passed to open()
    closed: bool
    async def aclose(self) -> None: ...
    def fileno(self) -> int: ...
    async def flush(self) -> None: ...
    def isatty(self) -> bool: ...
    async def read(self, n: int = ...) -> AnyStr: ...
    def readable(self) -> bool: ...
    async def readline(self, limit: int = ...) -> AnyStr: ...
    async def readlines(self, hint: int = ...) -> list[AnyStr]: ...
    async def seek(self, offset: int, whence: int = ...) -> int: ...
    def seekable(self) -> bool: ...
    async def tell(self) -> int: ...
    async def truncate(self, size: Optional[int] = ...) -> int: ...
    def writable(self) -> bool: ...
    async def write(self, s: AnyStr) -> int: ...
    async def writelines(self, lines: Iterable[AnyStr]) -> None: ...
    async def __anext__(self) -> AnyStr: ...
    def __aiter__(self) -> AsyncIterator[AnyStr]: ...
    async def __aenter__(self: _T) -> _T: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None: ...

class AsyncBinaryIO(AsyncIO[bytes]):
    pass

class AsyncTextIO(AsyncIO[str]):
    encoding: str
    errors: Optional[str]
    newlines: Union[str, Tuple[str, ...], None]

# Implementations: (from io.pyi, but simplified by removing the "Base" classes)
class AsyncFileIO(AsyncBinaryIO):
    async def readall(self) -> bytes: ...
    async def readinto(self, __buffer: WriteableBuffer) -> int: ...
    async def write(self, __b: ReadableBuffer) -> int: ...
    async def read(self, __size: int = ...) -> bytes: ...

class AsyncBufferedFileIO(AsyncFileIO):
    async def detach(self) -> AsyncBinaryIO: ...
    async def readinto1(self, __buffer: WriteableBuffer) -> int: ...
    async def read(self, __size: Optional[int] = ...) -> bytes: ...
    async def read1(self, __size: int = ...) -> bytes: ...
    def peek(self, __size: int = ...) -> bytes: ...

class AsyncTextFileIO(AsyncTextIO):
    async def detach(self) -> AsyncBinaryIO: ...
    async def read(self, __size: Optional[int] = ...) -> str: ...

# Backward compatibility aliases
_AsyncIOBase = AsyncIO[AnyStr]
_AsyncRawIOBase = AsyncFileIO
_AsyncBufferedIOBase = AsyncBufferedFileIO
_AsyncTextIOBase = AsyncTextFileIO

# open_file() overloads cribbed from typeshed builtins.open, with
# some simplifications:
_OpenFile = Union[StrOrBytesPath, int]
_Opener = Callable[[str, int], int]

# Text mode
@overload
async def open_file(
    file: _OpenFile,
    mode: OpenTextMode = ...,
    buffering: int = ...,
    encoding: Optional[str] = ...,
    errors: Optional[str] = ...,
    newline: Optional[str] = ...,
    closefd: bool = ...,
    opener: Optional[_Opener] = ...,
) -> AsyncTextFileIO: ...

# Unbuffered binary mode
@overload
async def open_file(
    file: _OpenFile,
    mode: OpenBinaryMode,
    buffering: Literal[0],
    encoding: None = ...,
    errors: None = ...,
    newline: None = ...,
    closefd: bool = ...,
    opener: Optional[_Opener] = ...,
) -> AsyncFileIO: ...

# Buffered binary mode
@overload
async def open_file(
    file: _OpenFile,
    mode: OpenBinaryMode,
    buffering: Literal[-1, 1] = ...,
    encoding: None = ...,
    errors: None = ...,
    newline: None = ...,
    closefd: bool = ...,
    opener: Optional[_Opener] = ...,
) -> AsyncBufferedFileIO: ...

# Buffering cannot be determined
@overload
async def open_file(
    file: _OpenFile,
    mode: OpenBinaryMode,
    buffering: int,
    encoding: None = ...,
    errors: None = ...,
    newline: None = ...,
    closefd: bool = ...,
    opener: Optional[_Opener] = ...,
) -> AsyncFileIO: ...

# Fallback if mode is not specified
@overload
async def open_file(
    file: _OpenFile,
    mode: str,
    buffering: int = ...,
    encoding: Optional[str] = ...,
    errors: Optional[str] = ...,
    newline: Optional[str] = ...,
    closefd: bool = ...,
    opener: Optional[_Opener] = ...,
) -> AsyncIO[Any]: ...
@overload
def wrap_file(file: Union[TextIO, io.TextIOBase]) -> AsyncTextIO: ...
@overload
def wrap_file(file: Union[BinaryIO, io.BufferedIOBase]) -> AsyncBinaryIO: ...
@overload
def wrap_file(file: io.RawIOBase) -> AsyncBinaryIO: ...
@overload
def wrap_file(file: Union[IO[Any], io.IOBase]) -> AsyncIO[Any]: ...

# _path
@final
class Path(pathlib.PurePath):
    @classmethod
    async def cwd(cls) -> Path: ...
    @classmethod
    async def home(cls) -> Path: ...
    async def stat(self) -> os.stat_result: ...
    async def chmod(self, mode: int) -> None: ...
    async def exists(self) -> bool: ...
    async def glob(self, pattern: str) -> Iterator[Path]: ...
    async def group(self) -> str: ...
    async def is_dir(self) -> bool: ...
    async def is_file(self) -> bool: ...
    async def is_symlink(self) -> bool: ...
    async def is_socket(self) -> bool: ...
    async def is_fifo(self) -> bool: ...
    async def is_block_device(self) -> bool: ...
    async def is_char_device(self) -> bool: ...
    async def iterdir(self) -> Iterator[Path]: ...
    async def lchmod(self, mode: int) -> None: ...
    async def lstat(self) -> os.stat_result: ...
    async def mkdir(
        self, mode: int = ..., parents: bool = ..., exist_ok: bool = ...
    ) -> None: ...
    @overload
    async def open(
        self,
        mode: OpenTextMode = ...,
        buffering: int = ...,
        encoding: Optional[str] = ...,
        errors: Optional[str] = ...,
        newline: Optional[str] = ...,
    ) -> AsyncTextFileIO: ...
    @overload
    async def open(
        self,
        mode: OpenBinaryMode,
        buffering: Literal[0],
        encoding: None = ...,
        errors: None = ...,
        newline: None = ...,
    ) -> AsyncFileIO: ...
    @overload
    async def open(
        self,
        mode: OpenBinaryMode,
        buffering: Literal[-1, 1] = ...,
        encoding: None = ...,
        errors: None = ...,
        newline: None = ...,
    ) -> AsyncBufferedFileIO: ...
    @overload
    async def open(
        self,
        mode: OpenBinaryMode,
        buffering: int,
        encoding: None = ...,
        errors: None = ...,
        newline: None = ...,
    ) -> AsyncFileIO: ...
    @overload
    async def open(
        self,
        mode: str,
        buffering: int = ...,
        encoding: Optional[str] = ...,
        errors: Optional[str] = ...,
        newline: Optional[str] = ...,
    ) -> AsyncIO[Any]: ...
    async def owner(self) -> str: ...
    async def rename(self, target: Union[str, pathlib.PurePath]) -> None: ...
    async def replace(self, target: Union[str, pathlib.PurePath]) -> None: ...
    if sys.version_info < (3, 6):
        async def resolve(self) -> Path: ...
    else:
        async def resolve(self, strict: bool = ...) -> Path: ...

    async def rglob(self, pattern: str) -> Iterator[Path]: ...
    async def rmdir(self) -> None: ...
    async def symlink_to(
        self, target: Union[str, pathlib.PurePath], target_is_directory: bool = ...
    ) -> None: ...
    async def touch(self, mode: int = ..., exist_ok: bool = ...) -> None: ...
    async def unlink(self) -> None: ...
    # added in 3.5:
    async def absolute(self) -> Path: ...
    async def expanduser(self) -> Path: ...
    async def read_bytes(self) -> bytes: ...
    async def read_text(
        self, encoding: Optional[str] = ..., errors: Optional[str] = ...
    ) -> str: ...
    async def samefile(self, other_path: Union[str, bytes, int, Path]) -> bool: ...
    async def write_bytes(self, data: bytes) -> int: ...
    async def write_text(
        self, data: str, encoding: Optional[str] = ..., errors: Optional[str] = ...
    ) -> int: ...

# _highlevel_serve_listeners
_T_resource = TypeVar("_T_resource", bound=trio.abc.AsyncResource)

async def serve_listeners(
    handler: Callable[[_T_resource], Awaitable[Any]],
    listeners: Sequence[trio.abc.Listener[_T_resource]],
    *,
    handler_nursery: Optional[Nursery] = None,
    task_status: TaskStatus[Sequence[trio.abc.Listener[_T_resource]]] = ...,
) -> NoReturn: ...

# _highlevel_open_tcp_stream
async def open_tcp_stream(
    host: Union[str, bytes],
    port: int,
    *,
    happy_eyeballs_delay: float = ...,
    local_address: Union[str, bytes, None] = ...,
) -> SocketStream: ...

# _highlevel_open_tcp_listeners
async def open_tcp_listeners(
    port: int, *, host: Optional[AnyStr] = None, backlog: Optional[int] = None
) -> Sequence[SocketListener]: ...
async def serve_tcp(
    handler: Callable[[SocketStream], Awaitable[Any]],
    port: int,
    *,
    host: Optional[AnyStr] = None,
    backlog: Optional[int] = None,
    handler_nursery: Optional[Nursery] = None,
    task_status: TaskStatus[Sequence[SocketListener]] = ...,
) -> NoReturn: ...

# _highlevel_open_unix_stream
async def open_unix_socket(filename: AnyStr) -> SocketStream: ...

# _highlevel_ssl_helpers
async def open_ssl_over_tcp_stream(
    host: AnyStr,
    port: int,
    *,
    https_compatible: bool = False,
    ssl_context: Optional[ssl.SSLContext] = None,
    happy_eyeballs_delay: float = ...,
) -> trio.SSLStream: ...
async def open_ssl_over_tcp_listeners(
    port: int,
    ssl_context: ssl.SSLContext,
    *,
    host: Optional[AnyStr] = None,
    https_compatible: bool = False,
    backlog: Optional[int] = None,
) -> Sequence[trio.SSLListener]: ...
async def serve_ssl_over_tcp(
    handler: Callable[[trio.SSLStream], Awaitable[Any]],
    port: int,
    ssl_context: ssl.SSLContext,
    *,
    host: Optional[AnyStr] = None,
    https_compatible: bool = False,
    backlog: Optional[int] = None,
    handler_nursery: Optional[Nursery] = None,
    task_status: TaskStatus[Sequence[trio.SSLListener]] = ...,
) -> NoReturn: ...

# _ssl
@final
class SSLStream(trio.abc.Stream):
    transport_stream: trio.abc.Stream
    context: ssl.SSLContext
    server_side: bool
    server_hostname: Optional[str]

    if sys.version_info >= (3, 6):
        @property
        def session(self) -> Optional[ssl.SSLSession]: ...
        @property
        def session_reused(self) -> bool: ...

    def __init__(
        self,
        transport_stream: trio.abc.Stream,
        ssl_context: ssl.SSLContext,
        *,
        server_hostname: Optional[str] = None,
        server_side: bool = False,
        https_compatible: bool = False,
    ) -> None: ...
    def getpeercert(self, binary_form: bool = ...) -> ssl._PeerCertRetType: ...
    def selected_npn_protocol(self) -> Optional[str]: ...
    def selected_alpn_protocol(self) -> Optional[str]: ...
    def cipher(self) -> Tuple[str, int, int]: ...
    def shared_ciphers(self) -> Optional[List[Tuple[str, int, int]]]: ...
    def compression(self) -> Optional[str]: ...
    def pending(self) -> int: ...
    def get_channel_binding(self, cb_type: str = ...) -> Optional[bytes]: ...
    async def do_handshake(self) -> None: ...
    async def unwrap(self) -> Tuple[trio.abc.Stream, bytes]: ...
    async def aclose(self) -> None: ...
    async def send_all(self, data: Union[bytes, memoryview]) -> None: ...
    async def wait_send_all_might_not_block(self) -> None: ...
    async def receive_some(self, max_bytes: Optional[int] = ...) -> bytes: ...

@final
class SSLListener(trio.abc.Listener[SSLStream]):
    transport_listener: trio.abc.Listener[trio.abc.Stream]
    def __init__(
        self,
        transport_listener: trio.abc.Listener[trio.abc.Stream],
        ssl_context: ssl.SSLContext,
        *,
        https_compatible: bool = False,
    ) -> None: ...
    async def accept(self) -> SSLStream: ...
    async def aclose(self) -> None: ...

# _subprocess

class _HasFileno(Protocol):
    def fileno(self) -> int: ...

_Redirect = Union[int, _HasFileno, None]

@final
class Process(_NotConstructible, metaclass=ABCMeta):
    stdin: Optional[trio.abc.SendStream]
    stdout: Optional[trio.abc.ReceiveStream]
    stderr: Optional[trio.abc.ReceiveStream]
    stdio: Optional[StapledStream]
    args: Union[str, Sequence[str]]
    pid: int
    @property
    def returncode(self) -> Optional[int]: ...
    async def wait(self) -> int: ...
    def poll(self) -> Optional[int]: ...
    def send_signal(self, sig: signal.Signals) -> None: ...
    def terminate(self) -> None: ...
    def kill(self) -> None: ...

# There's a lot of duplication here because mypy doesn't
# have a good way to represent overloads that differ only
# slightly. A cheat sheet:
# - on Windows, command is Union[str, Sequence[str]];
#   on Unix, command is str if shell=True and Sequence[str] otherwise
# - on Windows, there are startupinfo and creationflags options;
#   on Unix, there are preexec_fn, restore_signals, start_new_session, and pass_fds
# - run_process() has the signature of open_process() plus arguments
#   capture_stdout, capture_stderr, check, deliver_cancel, and the ability to pass
#   bytes as stdin

if sys.platform == "win32":
    async def run_process(
        command: Union[StrOrBytesPath, Sequence[StrOrBytesPath]],
        *,
        task_status: TaskStatus[Process] = ...,
        stdin: Union[bytes, _Redirect] = ...,
        capture_stdout: bool = ...,
        capture_stderr: bool = ...,
        check: bool = ...,
        deliver_cancel: Optional[Callable[[Process], Awaitable[None]]] = ...,
        stdout: _Redirect = ...,
        stderr: _Redirect = ...,
        close_fds: bool = ...,
        shell: bool = ...,
        cwd: Optional[StrOrBytesPath] = ...,
        env: Optional[Mapping[str, str]] = ...,
        startupinfo: subprocess.STARTUPINFO = ...,
        creationflags: int = ...,
    ) -> subprocess.CompletedProcess[bytes]: ...

else:
    @overload
    async def run_process(
        command: StrOrBytesPath,
        *,
        task_status: TaskStatus[Process] = ...,
        stdin: Union[bytes, _Redirect] = ...,
        capture_stdout: bool = ...,
        capture_stderr: bool = ...,
        check: bool = ...,
        deliver_cancel: Optional[Callable[[Process], Awaitable[None]]] = ...,
        stdout: _Redirect = ...,
        stderr: _Redirect = ...,
        close_fds: bool = ...,
        shell: Literal[True],
        cwd: Optional[StrOrBytesPath] = ...,
        env: Optional[Mapping[str, str]] = ...,
        preexec_fn: Optional[Callable[[], Any]] = ...,
        restore_signals: bool = ...,
        start_new_session: bool = ...,
        pass_fds: Sequence[int] = ...,
    ) -> subprocess.CompletedProcess[bytes]: ...
    @overload
    async def run_process(
        command: Sequence[StrOrBytesPath],
        *,
        task_status: TaskStatus[Process] = ...,
        stdin: Union[bytes, _Redirect] = ...,
        capture_stdout: bool = ...,
        capture_stderr: bool = ...,
        check: bool = ...,
        deliver_cancel: Optional[Callable[[Process], Awaitable[None]]] = ...,
        stdout: _Redirect = ...,
        stderr: _Redirect = ...,
        close_fds: bool = ...,
        shell: bool = ...,
        cwd: Optional[StrOrBytesPath] = ...,
        env: Optional[Mapping[str, str]] = ...,
        preexec_fn: Optional[Callable[[], Any]] = ...,
        restore_signals: bool = ...,
        start_new_session: bool = ...,
        pass_fds: Sequence[int] = ...,
    ) -> subprocess.CompletedProcess[bytes]: ...
