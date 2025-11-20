from typing import (
    Any,
    AsyncContextManager,
    AsyncIterator,
    Awaitable,
    Callable,
    ContextManager,
    Coroutine,
    Generic,
    Iterator,
    Mapping,
    NoReturn,
    Optional,
    Sequence,
    Union,
    Sequence,
    TypeVar,
    Tuple,
    overload,
    final,
    cast,
)
from types import FrameType
from abc import ABCMeta
from _typeshed import StrOrBytesPath
from trio_typing import Nursery, takes_callable_and_args
from typing_extensions import Literal, Protocol
from mypy_extensions import VarArg
import attr
import trio
import outcome
import contextvars
import enum
import select
import sys

_T = TypeVar("_T")
_F = TypeVar("_F", bound=Callable[..., Any])

# _core._ki
def enable_ki_protection(fn: _F) -> _F: ...
def disable_ki_protection(fn: _F) -> _F: ...
def currently_ki_protected() -> bool: ...

# _core._entry_queue
@final
@attr.s(eq=False, hash=False, slots=True)
class TrioToken(metaclass=ABCMeta):
    @takes_callable_and_args
    def run_sync_soon(
        self,
        sync_fn: Union[Callable[..., Any], Callable[[VarArg()], Any]],
        *args: Any,
        idempotent: bool = False,
    ) -> None: ...

# _core._unbounded_queue
@attr.s(slots=True, frozen=True)
class UnboundedQueueStatistics:
    qsize: int = attr.ib()
    tasks_waiting: int = attr.ib()

@final
class UnboundedQueue(Generic[_T], metaclass=ABCMeta):
    def __init__(self) -> None: ...
    def qsize(self) -> int: ...
    def empty(self) -> bool: ...
    def put_nowait(self, obj: _T) -> None: ...
    def get_batch_nowait(self) -> Sequence[_T]: ...
    async def get_batch(self) -> Sequence[_T]: ...
    def statistics(self) -> UnboundedQueueStatistics: ...
    def __aiter__(self) -> AsyncIterator[Sequence[_T]]: ...
    async def __anext__(self) -> Sequence[_T]: ...

# _core._run
if sys.platform == "win32":
    @attr.frozen
    class _IOStatistics:
        tasks_waiting_read: int = attr.ib()
        tasks_waiting_write: int = attr.ib()
        tasks_waiting_overlapped: int = attr.ib()
        completion_key_monitors: int = attr.ib()
        backend: Literal["windows"] = attr.ib(init=False, default="windows")

elif sys.platform == "linux":
    @attr.frozen
    class _IOStatistics:
        tasks_waiting_read: int = attr.ib()
        tasks_waiting_write: int = attr.ib()
        backend: Literal["epoll"] = attr.ib(init=False, default="epoll")

else:  # kqueue
    @attr.frozen
    class _IOStatistics:
        tasks_waiting: int = attr.ib()
        monitors: int = attr.ib()
        backend: Literal["kqueue"] = attr.ib(init=False, default="kqueue")

@attr.frozen
class RunStatistics:
    tasks_living: int
    tasks_runnable: int
    seconds_to_next_deadline: float
    io_statistics: _IOStatistics
    run_sync_soon_queue_size: int

@final
@attr.s(eq=False, hash=False, repr=False, slots=True)
class Task(metaclass=ABCMeta):
    coro: Coroutine[Any, outcome.Outcome[object], Any]
    name: str
    context: contextvars.Context
    custom_sleep_data: Any
    @property
    def parent_nursery(self) -> Optional[Nursery]: ...
    @property
    def eventual_parent_nursery(self) -> Optional[Nursery]: ...
    @property
    def child_nurseries(self) -> Sequence[Nursery]: ...
    def iter_await_frames(self) -> Iterator[Tuple[FrameType, int]]: ...

async def checkpoint() -> None: ...
async def checkpoint_if_cancelled() -> None: ...
def current_task() -> Task: ...
def current_root_task() -> Task: ...
def current_statistics() -> RunStatistics: ...
def current_clock() -> trio.abc.Clock: ...
def current_trio_token() -> TrioToken: ...
def reschedule(task: Task, next_send: outcome.Outcome[Any] = ...) -> None: ...
@takes_callable_and_args
def spawn_system_task(
    async_fn: Union[
        Callable[..., Awaitable[Any]], Callable[[VarArg()], Awaitable[Any]]
    ],
    *args: Any,
    name: object = ...,
) -> Task: ...
def add_instrument(instrument: trio.abc.Instrument) -> None: ...
def remove_instrument(instrument: trio.abc.Instrument) -> None: ...
async def wait_readable(fd: int) -> None: ...
async def wait_writable(fd: int) -> None: ...
def notify_closing(fd: int) -> None: ...
@takes_callable_and_args
def start_guest_run(
    afn: Union[Callable[..., Awaitable[_T]], Callable[[VarArg()], Awaitable[_T]]],
    *args: Any,
    run_sync_soon_threadsafe: Callable[[Callable[[], None]], None],
    done_callback: Callable[[outcome.Outcome[_T]], None],
    run_sync_soon_not_threadsafe: Callable[[Callable[[], None]], None] = ...,
    host_uses_signal_set_wakeup_fd: bool = ...,
    clock: Optional[trio.abc.Clock] = ...,
    instruments: Sequence[trio.abc.Instrument] = ...,
    restrict_keyboard_interrupt_to_checkpoints: bool = ...,
    strict_exception_groups: bool = ...,
) -> None: ...

# kqueue only
if sys.platform == "darwin" or sys.platform.startswith("freebsd"):
    def current_kqueue() -> select.kqueue: ...
    def monitor_kevent(
        ident: int, filter: int
    ) -> ContextManager[UnboundedQueue[select.kevent]]: ...
    async def wait_kevent(
        ident: int, filter: int, abort_func: Callable[[Callable[[], NoReturn]], Abort]
    ) -> select.kevent: ...

# windows only
if sys.platform == "win32":
    class _CompletionKeyEventInfo:
        lpOverlapped: int
        dwNumberOfBytesTransferred: int
    def current_iocp() -> int: ...
    def register_with_iocp(handle: int) -> None: ...
    async def wait_overlapped(handle: int, lpOverlapped: int) -> None: ...
    def monitor_completion_key() -> (
        ContextManager[Tuple[int, UnboundedQueue[_CompletionKeyEventInfo]]]
    ): ...

# _core._traps
class Abort(enum.Enum):
    SUCCEEDED = 1
    FAILED = 2

async def cancel_shielded_checkpoint() -> None: ...
async def wait_task_rescheduled(
    abort_func: Callable[[Callable[[], NoReturn]], Abort]
) -> Any: ...
async def permanently_detach_coroutine_object(
    final_outcome: outcome.Outcome[object],
) -> Any: ...
async def temporarily_detach_coroutine_object(
    abort_func: Callable[[Callable[[], NoReturn]], Abort]
) -> Any: ...
async def reattach_detached_coroutine_object(task: Task, yield_value: Any) -> None: ...

# _core._parking_lot
@attr.s(frozen=True, slots=True)
class ParkingLotStatistics:
    tasks_waiting: int = attr.ib()

@final
@attr.s(eq=False, hash=False, slots=True)
class ParkingLot(metaclass=ABCMeta):
    def __len__(self) -> int: ...
    def __bool__(self) -> bool: ...
    async def park(self) -> None: ...
    def unpark(self, *, count: int = 1) -> Sequence[Task]: ...
    def unpark_all(self) -> Sequence[Task]: ...
    def repark(self, new_lot: ParkingLot, *, count: int = 1) -> None: ...
    def repark_all(self, new_lot: ParkingLot) -> None: ...
    def statistics(self) -> ParkingLotStatistics: ...

# _core._local
class _NoValue: ...

@final
@attr.s(eq=False, hash=False, slots=True)
class RunVarToken(Generic[_T], metaclass=ABCMeta):
    _var: RunVar[_T] = attr.ib()
    previous_value: _T | type[_NoValue] = attr.ib(default=_NoValue)
    redeemed: bool = attr.ib(init=False)

@final
@attr.s(eq=False, hash=False, slots=True)
class RunVar(Generic[_T], metaclass=ABCMeta):
    _name: str = attr.ib()
    _default: _T = attr.ib(default=cast(_T, object()))
    def get(self, default: _T = ...) -> _T: ...
    def set(self, value: _T) -> RunVarToken[_T]: ...
    def reset(self, token: RunVarToken[_T]) -> None: ...

# _core._thread_cache
def start_thread_soon(
    fn: Callable[[], _T],
    deliver: Callable[[outcome.Outcome[_T]], None],
    name: Optional[str] = ...,
) -> None: ...

# _subprocess

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

class _HasFileno(Protocol):
    def fileno(self) -> int: ...

_Redirect = Union[int, _HasFileno, None]

if sys.platform == "win32":
    async def open_process(
        command: Union[StrOrBytesPath, Sequence[StrOrBytesPath]],
        *,
        stdin: _Redirect = ...,
        stdout: _Redirect = ...,
        stderr: _Redirect = ...,
        close_fds: bool = ...,
        shell: bool = ...,
        cwd: Optional[StrOrBytesPath] = ...,
        env: Optional[Mapping[str, str]] = ...,
        startupinfo: subprocess.STARTUPINFO = ...,
        creationflags: int = ...,
    ) -> trio.Process: ...

else:
    @overload
    async def open_process(
        command: StrOrBytesPath,
        *,
        stdin: _Redirect = ...,
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
    ) -> trio.Process: ...
    @overload
    async def open_process(
        command: Sequence[StrOrBytesPath],
        *,
        stdin: _Redirect = ...,
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
    ) -> trio.Process: ...

# _unix_pipes
@final
class FdStream(trio.abc.Stream):
    def __init__(self, fd: int): ...
    async def send_all(self, data: Union[bytes, memoryview]) -> None: ...
    async def wait_send_all_might_not_block(self) -> None: ...
    async def receive_some(self, max_bytes: Optional[int] = ...) -> bytes: ...
    async def aclose(self) -> None: ...
    def fileno(self) -> int: ...

# _wait_for_object
async def WaitForSingleObject(obj: int) -> None: ...
