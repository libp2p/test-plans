import sys
from functools import partial
from typing import Callable, List, Optional, Sequence, Tuple, cast
from typing_extensions import Literal
from typing import Type as typing_Type
from mypy import message_registry
from mypy.plugin import Plugin, FunctionContext, MethodContext, CheckerPluginInterface
from mypy.nodes import (
    ARG_POS,
    ARG_STAR,
    TypeInfo,
    Context,
    FuncDef,
    StrExpr,
    IntExpr,
    Expression,
)
from mypy.types import (
    Type,
    CallableType,
    NoneTyp,
    Overloaded,
    TypeVarLikeType,
    TypeVarType,
    Instance,
    UnionType,
    UninhabitedType,
    AnyType,
    TypeOfAny,
    get_proper_type,
    get_proper_types,
)
from mypy.typeops import make_simplified_union
from mypy.checker import TypeChecker
from packaging.version import parse as parse_version


class TrioPlugin(Plugin):
    def get_function_hook(
        self, fullname: str
    ) -> Optional[Callable[[FunctionContext], Type]]:
        if fullname == "trio_typing.takes_callable_and_args":
            return takes_callable_and_args_callback
        if fullname == "async_generator.async_generator":
            return async_generator_callback
        if fullname == "async_generator.yield_":
            return yield_callback
        if fullname == "async_generator.yield_from_":
            return yield_from_callback
        return None


class TrioPlugin13(TrioPlugin):
    def get_function_hook(
        self, fullname: str
    ) -> Optional[Callable[[FunctionContext], Type]]:
        if fullname == "trio_typing.takes_callable_and_args":
            return partial(takes_callable_and_args_callback, has_type_var_default=False)

        return super().get_function_hook(fullname)


def decode_agen_types_from_return_type(
    ctx: FunctionContext, original_async_return_type: Type
) -> Tuple[Type, Type, Type]:
    """Return the yield type, send type, and return type of
    an @async_generator decorated function that was
    originally declared to return ``original_async_return_type``.

    This tries to interpret ``original_async_return_type`` as a union
    between the async generator return type (i.e., the thing actually
    returned by the decorated function, which becomes the value
    associated with a ``StopAsyncIteration`` exception), an optional
    ``trio_typing.YieldType[X]`` where ``X`` is the type of values
    that the async generator yields, and an optional
    ``trio_typing.SendType[Y]`` where ``Y`` is the type of values that
    the async generator expects to be sent. If one of ``YieldType``
    and ``SendType`` is specified, the other is assumed to be None;
    if neither is specified, both are assumed to be Any.
    If ``original_async_return_type`` includes a ``YieldType``
    and/or a ``SendType`` but no actual return type, the return
    is inferred as ``NoReturn``.
    """

    arms = []  # type: Sequence[Type]
    resolved_async_return_type = get_proper_type(original_async_return_type)
    if isinstance(resolved_async_return_type, UnionType):
        arms = resolved_async_return_type.items
    else:
        arms = [original_async_return_type]
    yield_type = None  # type: Optional[Type]
    send_type = None  # type: Optional[Type]
    other_arms = []  # type: List[Type]
    try:
        for orig_arm in arms:
            arm = get_proper_type(orig_arm)
            if isinstance(arm, Instance):
                if arm.type.fullname == "trio_typing.YieldType":
                    if len(arm.args) != 1:
                        raise ValueError("YieldType must take one argument")
                    if yield_type is not None:
                        raise ValueError("YieldType specified multiple times")
                    yield_type = arm.args[0]
                elif arm.type.fullname == "trio_typing.SendType":
                    if len(arm.args) != 1:
                        raise ValueError("SendType must take one argument")
                    if send_type is not None:
                        raise ValueError("SendType specified multiple times")
                    send_type = arm.args[0]
                else:
                    other_arms.append(orig_arm)
            else:
                other_arms.append(orig_arm)
    except ValueError as ex:
        ctx.api.fail("invalid @async_generator return type: {}".format(ex), ctx.context)
        return (
            AnyType(TypeOfAny.from_error),
            AnyType(TypeOfAny.from_error),
            original_async_return_type,
        )

    if yield_type is None and send_type is None:
        return (
            AnyType(TypeOfAny.unannotated),
            AnyType(TypeOfAny.unannotated),
            original_async_return_type,
        )

    if yield_type is None:
        yield_type = NoneTyp(ctx.context.line, ctx.context.column)
    if send_type is None:
        send_type = NoneTyp(ctx.context.line, ctx.context.column)
    if not other_arms:
        return (
            yield_type,
            send_type,
            UninhabitedType(
                is_noreturn=True, line=ctx.context.line, column=ctx.context.column
            ),
        )
    else:
        return (
            yield_type,
            send_type,
            make_simplified_union(other_arms, ctx.context.line, ctx.context.column),
        )


def async_generator_callback(ctx: FunctionContext) -> Type:
    """Handle @async_generator.

    This moves the yield type and send type declarations from
    the return type of the decorated function to the appropriate
    type parameters of ``trio_typing.CompatAsyncGenerator``.
    That is, if you say::

        @async_generator
        async def example() -> Union[str, YieldType[bool], SendType[int]]:
            ...

    then the decorated ``example()`` will return values of type
    ``CompatAsyncGenerator[bool, int, str]``, as opposed to
    ``CompatAsyncGenerator[Any, Any, Union[str,
    YieldType[bool], SendType[int]]`` without the plugin.
    """

    decorator_return_type = ctx.default_return_type
    if not isinstance(decorator_return_type, CallableType):
        return decorator_return_type
    agen_return_type = get_proper_type(decorator_return_type.ret_type)
    if (
        isinstance(agen_return_type, Instance)
        and agen_return_type.type.fullname == "trio_typing.CompatAsyncGenerator"
        and len(agen_return_type.args) == 3
    ):
        return decorator_return_type.copy_modified(
            ret_type=agen_return_type.copy_modified(
                args=list(
                    decode_agen_types_from_return_type(ctx, agen_return_type.args[2])
                )
            )
        )
    return decorator_return_type


def decode_enclosing_agen_types(ctx: FunctionContext) -> Tuple[Type, Type]:
    """Return the yield and send types that would be returned by
    decode_agen_types_from_return_type() for the function that's
    currently being typechecked, i.e., the function that contains the
    call described in ``ctx``.
    """
    private_api = cast(TypeChecker, ctx.api)
    enclosing_func = private_api.scope.top_function()
    if (
        enclosing_func is None
        or not isinstance(enclosing_func, FuncDef)
        or not enclosing_func.is_coroutine
        or not enclosing_func.is_decorated
    ):
        # we can't actually detect the @async_generator decorator but
        # we'll at least notice if it couldn't possibly be present
        ctx.api.fail(
            "async_generator.yield_() outside an @async_generator func", ctx.context
        )
        return AnyType(TypeOfAny.from_error), AnyType(TypeOfAny.from_error)

    # The enclosing function type Callable[...] and its return type
    # Coroutine[...]  were both produced by mypy, rather than typed by
    # the user, so they can't be type aliases; thus there's no need to
    # use get_proper_type() here.
    if (
        isinstance(enclosing_func.type, CallableType)
        and isinstance(enclosing_func.type.ret_type, Instance)
        and enclosing_func.type.ret_type.type.fullname == "typing.Coroutine"
        and len(enclosing_func.type.ret_type.args) == 3
    ):
        yield_type, send_type, _ = decode_agen_types_from_return_type(
            ctx, enclosing_func.type.ret_type.args[2]
        )
        return yield_type, send_type

    return (
        AnyType(TypeOfAny.implementation_artifact),
        AnyType(TypeOfAny.implementation_artifact),
    )


def yield_callback(ctx: FunctionContext) -> Type:
    """Provide a more specific argument and return type for yield_()
    inside an @async_generator.
    """
    if len(ctx.arg_types) == 0:
        arg_type = NoneTyp(ctx.context.line, ctx.context.column)  # type: Type
    elif ctx.arg_types and len(ctx.arg_types[0]) == 1:
        arg_type = ctx.arg_types[0][0]
    else:
        return ctx.default_return_type

    private_api = cast(TypeChecker, ctx.api)
    yield_type, send_type = decode_enclosing_agen_types(ctx)
    if yield_type is not None and send_type is not None:
        private_api.check_subtype(
            subtype=arg_type,
            supertype=yield_type,
            context=ctx.context,
            msg=message_registry.INCOMPATIBLE_TYPES,
            subtype_label="yield_ argument",
            supertype_label="declared YieldType",
        )
        return ctx.api.named_generic_type("typing.Awaitable", [send_type])

    return ctx.default_return_type


def yield_from_callback(ctx: FunctionContext) -> Type:
    """Provide a better typecheck for yield_from_()."""
    if ctx.arg_types and len(ctx.arg_types[0]) == 1:
        arg_type = get_proper_type(ctx.arg_types[0][0])
    else:
        return ctx.default_return_type

    private_api = cast(TypeChecker, ctx.api)
    our_yield_type, our_send_type = decode_enclosing_agen_types(ctx)
    if our_yield_type is None or our_send_type is None:
        return ctx.default_return_type

    if (
        isinstance(arg_type, Instance)
        and arg_type.type.fullname
        in (
            "trio_typing.CompatAsyncGenerator",
            "trio_typing.AsyncGenerator",
            "typing.AsyncGenerator",
        )
        and len(arg_type.args) >= 2
    ):
        their_yield_type, their_send_type = arg_type.args[:2]
        private_api.check_subtype(
            subtype=their_yield_type,
            supertype=our_yield_type,
            context=ctx.context,
            msg=message_registry.INCOMPATIBLE_TYPES,
            subtype_label="yield_from_ argument YieldType",
            supertype_label="local declared YieldType",
        )
        private_api.check_subtype(
            subtype=our_send_type,
            supertype=their_send_type,
            context=ctx.context,
            msg=message_registry.INCOMPATIBLE_TYPES,
            subtype_label="local declared SendType",
            supertype_label="yield_from_ argument SendType",
        )
    elif isinstance(arg_type, Instance):
        private_api.check_subtype(
            subtype=arg_type,
            supertype=ctx.api.named_generic_type(
                "typing.AsyncIterable", [our_yield_type]
            ),
            context=ctx.context,
            msg=message_registry.INCOMPATIBLE_TYPES,
            subtype_label="yield_from_ argument type",
            supertype_label="expected iterable type",
        )

    return ctx.default_return_type


def takes_callable_and_args_callback(
    ctx: FunctionContext, has_type_var_default: bool = True
) -> Type:
    """Automate the boilerplate for writing functions that accept
    arbitrary positional arguments of the same type accepted by
    a callable.

    For example, this supports writing::

        @trio_typing.takes_callable_and_args
        def start_soon(
            self,
            async_fn: Callable[[VarArg()], Any],
            *args: Any,
        ) -> None: ...

    instead of::

        T1 = TypeVar("T1")
        T2 = TypeVar("T2")
        T3 = TypeVar("T3")
        T4 = TypeVar("T4")

        @overload
        def start_soon(
            self,
            async_fn: Callable[[], Any],
        ) -> None: ...

        @overload
        def start_soon(
            self,
            async_fn: Callable[[T1], Any],
            __arg1: T1,
        ) -> None: ...

        @overload
        def start_soon(
            self,
            async_fn: Callable[[T1, T2], Any],
            __arg1: T1,
            __arg2: T2
        ) -> None: ...

        # etc

    """
    try:
        if not ctx.arg_types or len(ctx.arg_types[0]) != 1:
            raise ValueError("must be used as a decorator")

        fn_type = get_proper_type(ctx.arg_types[0][0])
        if not isinstance(fn_type, CallableType) or not isinstance(
            get_proper_type(ctx.default_return_type), CallableType
        ):
            raise ValueError("must be used as a decorator")

        callable_idx = -1  # index in function arguments of the callable
        callable_args_idx = -1  # index in callable arguments of the StarArgs
        callable_ty = None  # type: Optional[CallableType]
        args_idx = -1  # index in function arguments of the StarArgs

        for idx, (kind, ty) in enumerate(zip(fn_type.arg_kinds, fn_type.arg_types)):
            ty = get_proper_type(ty)
            if isinstance(ty, AnyType) and kind == ARG_STAR:
                assert args_idx == -1
                args_idx = idx
            elif isinstance(ty, (UnionType, CallableType)) and kind == ARG_POS:
                # turn Union[Callable[..., T], Callable[[VarArg()], T]]
                # into Callable[[VarArg()], T]
                # (the union makes it not fail when the plugin is not being used)
                if isinstance(ty, UnionType):
                    for arm in get_proper_types(ty.items):
                        if (
                            isinstance(arm, CallableType)
                            and not arm.is_ellipsis_args
                            and any(kind_ == ARG_STAR for kind_ in arm.arg_kinds)
                        ):
                            ty = arm
                            break
                    else:
                        continue

                for idx_, (kind_, ty_) in enumerate(zip(ty.arg_kinds, ty.arg_types)):
                    ty_ = get_proper_type(ty_)
                    if isinstance(ty_, AnyType) and kind_ == ARG_STAR:
                        if callable_idx != -1:
                            raise ValueError(
                                "decorated function may only take one callable "
                                "that has an argument of type VarArg()"
                            )
                        callable_idx = idx
                        callable_args_idx = idx_
                        callable_ty = ty

        if args_idx == -1:
            raise ValueError("decorated function must take *args: Any")
        if callable_idx == -1 or callable_ty is None:
            raise ValueError(
                "decorated function must take a callable that has a "
                "argument of type mypy_extensions.VarArg()"
            )

        expanded_fns = []  # type: List[CallableType]
        type_var_types = []  # type: List[TypeVarType]
        for arg_idx in range(1, 7):  # provides overloads for 0 through 5 arguments
            arg_types = list(fn_type.arg_types)
            arg_types[callable_idx] = callable_ty.copy_modified(
                arg_types=(
                    callable_ty.arg_types[:callable_args_idx]
                    + cast(List[Type], type_var_types)
                    + callable_ty.arg_types[callable_args_idx + 1 :]
                ),
                arg_kinds=(
                    callable_ty.arg_kinds[:callable_args_idx]
                    + ([ARG_POS] * len(type_var_types))
                    + callable_ty.arg_kinds[callable_args_idx + 1 :]
                ),
                arg_names=(
                    callable_ty.arg_names[:callable_args_idx]
                    + ([None] * len(type_var_types))
                    + callable_ty.arg_names[callable_args_idx + 1 :]
                ),
                # Note that we do *not* append `type_var_types` to
                # `callable_ty.variables`. Even though `*type_var_types` are in our new
                # `callable_ty`'s argument types, they are *not* type variables that get
                # bound when our new `callable_ty` gets called. They get bound when the
                # `expanded_fn` that references our new `callable_ty` gets called.
            )
            expanded_fns.append(
                fn_type.copy_modified(
                    arg_types=(
                        arg_types[:args_idx]
                        + cast(List[Type], type_var_types)
                        + arg_types[args_idx + 1 :]
                    ),
                    arg_kinds=(
                        fn_type.arg_kinds[:args_idx]
                        + ([ARG_POS] * len(type_var_types))
                        + fn_type.arg_kinds[args_idx + 1 :]
                    ),
                    arg_names=(
                        fn_type.arg_names[:args_idx]
                        + ([None] * len(type_var_types))
                        + fn_type.arg_names[args_idx + 1 :]
                    ),
                    variables=(
                        list(fn_type.variables)
                        + cast(List[TypeVarLikeType], type_var_types)
                    ),
                )
            )

            if has_type_var_default:
                type_var_types.append(
                    TypeVarType(
                        "__T{}".format(arg_idx),
                        "__T{}".format(arg_idx),
                        -len(fn_type.variables) - arg_idx - 1,
                        [],
                        ctx.api.named_generic_type("builtins.object", []),
                        line=ctx.context.line,
                        column=ctx.context.column,
                        default=AnyType(TypeOfAny.from_omitted_generics),
                    )
                )
            else:
                type_var_types.append(
                    TypeVarType(
                        "__T{}".format(arg_idx),
                        "__T{}".format(arg_idx),
                        -len(fn_type.variables) - arg_idx - 1,
                        [],
                        ctx.api.named_generic_type("builtins.object", []),
                        line=ctx.context.line,
                        column=ctx.context.column,
                    )  # type: ignore[call-arg]
                )

        return Overloaded(expanded_fns)

    except ValueError as ex:
        ctx.api.fail(
            "invalid use of @takes_callable_and_args: {}".format(ex), ctx.context
        )
        return ctx.default_return_type


def plugin(version: str) -> typing_Type[Plugin]:
    mypy_version = parse_version(version)

    if mypy_version < parse_version("1.0"):
        raise RuntimeError("This version of trio-typing requires at least mypy 1.0.")
    elif mypy_version < parse_version("1.4"):
        return TrioPlugin13
    else:
        return TrioPlugin
