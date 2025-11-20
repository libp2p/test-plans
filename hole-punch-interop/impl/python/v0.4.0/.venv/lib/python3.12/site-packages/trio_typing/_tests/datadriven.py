# Adapts mypy.test.data pytest plugin for use outside the mypy tree

import os
import sys
import types
import pytest

data_prefix = os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "trio_typing/_tests/test-data"
)


class ConfigModule(types.ModuleType):
    def __init__(self) -> None:
        self.test_data_prefix = data_prefix
        self.PREFIX = os.path.dirname(os.path.realpath(__file__))
        self.test_temp_dir = "tmp"


sys.modules["mypy.test.config"] = ConfigModule()

from mypy.test.data import *


# pytest has deprecated direct construction of Node subclasses, but mypy.test.data
# still does it. Hack to make that OK.


class PatchedNodeMeta(type(pytest.Collector)):
    def __call__(cls, *args, **kw):
        return type.__call__(cls, *args, **kw)


DataSuiteCollector.__class__ = PatchedNodeMeta
DataDrivenTestCase.__class__ = PatchedNodeMeta
