import trio
from typing import Any, Awaitable, Callable, Optional, TypeVar, Union
from trio_typing import takes_callable_and_args
from mypy_extensions import VarArg

_T = TypeVar("_T")

@takes_callable_and_args
def run(
    afn: Union[Callable[..., Awaitable[_T]], Callable[[VarArg()], Awaitable[_T]]],
    *args: Any,
    trio_token: Optional[trio.lowlevel.TrioToken] = ...,
) -> _T: ...
@takes_callable_and_args
def run_sync(
    fn: Union[Callable[..., _T], Callable[[VarArg()], _T]],
    *args: Any,
    trio_token: Optional[trio.lowlevel.TrioToken] = ...,
) -> _T: ...
def check_cancelled() -> None: ...
