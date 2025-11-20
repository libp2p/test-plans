from typing import (
    Any,
    Awaitable,
    Callable,
    Generator,
    Generic,
    NoReturn,
    Optional,
    Type,
    TypeVar,
    Union,
)
from types import TracebackType
from typing_extensions import Protocol, ParamSpec

T = TypeVar("T")
U = TypeVar("U")
T_co = TypeVar("T_co", covariant=True)
T_contra = TypeVar("T_contra", contravariant=True)
P = ParamSpec("P")

# Can't use AsyncGenerator as it creates a dependency cycle
# (outcome stubs -> trio_typing stubs -> trio.hazmat stubs -> outcome)
class _ASendable(Protocol[T_contra, T_co]):
    def asend(self, value: T_contra) -> Awaitable[T_co]: ...
    def athrow(
        self,
        exc_type: Type[BaseException],
        exc_value: Optional[BaseException] = ...,
        exc_traceback: Optional[TracebackType] = ...,
    ) -> Awaitable[T_co]: ...

class Value(Generic[T]):
    value: T
    __match_args__ = ("value",)
    def __init__(self, value: T): ...
    def unwrap(self) -> T: ...
    def send(self, gen: Generator[U, T, Any]) -> U: ...
    async def asend(self, gen: _ASendable[T, U]) -> U: ...

class Error:
    error: BaseException
    __match_args__ = ("error",)
    def __init__(self, error: BaseException): ...
    def unwrap(self) -> NoReturn: ...
    def send(self, gen: Generator[U, Any, Any]) -> U: ...
    async def asend(self, gen: _ASendable[Any, U]) -> U: ...

Outcome = Union[Value[T], Error]

def capture(
    sync_fn: Callable[P, T], *args: P.args, **kwargs: P.kwargs
) -> Outcome[T]: ...
async def acapture(
    async_fn: Callable[P, Awaitable[T]], *args: P.args, **kwargs: P.kwargs
) -> Outcome[T]: ...
