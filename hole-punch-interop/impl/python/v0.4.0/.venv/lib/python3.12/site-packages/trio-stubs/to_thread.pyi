import trio
from typing import Any, Callable, Optional, TypeVar, Union
from trio_typing import takes_callable_and_args
from mypy_extensions import VarArg

_T = TypeVar("_T")

def current_default_thread_limiter() -> trio.CapacityLimiter: ...
@takes_callable_and_args
async def run_sync(
    sync_fn: Union[Callable[..., _T], Callable[[VarArg()], _T]],
    *args: Any,
    cancellable: bool = False,
    limiter: Optional[trio.CapacityLimiter] = None,
) -> _T: ...
