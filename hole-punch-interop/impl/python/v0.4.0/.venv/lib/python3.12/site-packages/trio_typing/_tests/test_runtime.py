import sys
import typing
import trio
import trio_typing
import async_generator


@async_generator.async_generator
async def compat_agen():
    pass


if sys.version_info >= (3, 6):
    exec("async def native_agen():\n  yield 42\n")
else:
    native_agen = compat_agen


def test_runtime():
    assert isinstance(compat_agen(), trio_typing.AsyncGenerator)
    assert isinstance(native_agen(), trio_typing.AsyncGenerator)
    if hasattr(typing, "AsyncGenerator"):
        assert trio_typing.AsyncGenerator is typing.AsyncGenerator

    async def task(*, task_status=trio.TASK_STATUS_IGNORED):
        assert isinstance(task_status, trio_typing.TaskStatus)
        task_status.started()

    async def main():
        async with trio.open_nursery() as nursery:
            assert isinstance(nursery, trio_typing.Nursery)
            nursery.start_soon(task)
            await nursery.start(task)
