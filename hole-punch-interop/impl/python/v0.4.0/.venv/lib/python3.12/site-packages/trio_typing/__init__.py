import abc as _abc
import sys as _sys
import typing as _t
import typing_extensions as _tx
import async_generator as _ag
import trio as _trio
from trio import Nursery
from ._version import __version__

__all__ = [
    "takes_callable_and_args",
    "Nursery",
    "TaskStatus",
    "AsyncGenerator",
    "CompatAsyncGenerator",
    "YieldType",
    "SendType",
]

_T = _t.TypeVar("_T")
_T_co = _t.TypeVar("_T_co", covariant=True)
_T_co2 = _t.TypeVar("_T_co2", covariant=True)
_T_contra = _t.TypeVar("_T_contra", contravariant=True)


def takes_callable_and_args(fn):
    return fn


class TaskStatus(_t.Generic[_T], metaclass=_abc.ABCMeta):
    pass


TaskStatus.register(_trio._core._run._TaskStatus)
TaskStatus.register(type(_trio.TASK_STATUS_IGNORED))

if _sys.version_info >= (3, 6):
    from typing import AsyncGenerator

else:

    class AsyncGenerator(_tx.AsyncIterator[_T_co], _t.Generic[_T_co, _T_contra]):
        pass


class CompatAsyncGenerator(
    AsyncGenerator[_T_co, _T_contra], _t.Generic[_T_co, _T_contra, _T_co2]
):
    pass


CompatAsyncGenerator.register(_ag._impl.AsyncGenerator)


class YieldType(_t.Generic[_T_co]):
    pass


class SendType(_t.Generic[_T_contra]):
    pass
