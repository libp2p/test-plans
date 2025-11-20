import os
import sys
from packaging.version import parse as parse_version
from importlib_metadata import version


if "trio_typing._tests.datadriven" not in sys.modules:

    def test_typecheck_dummy():
        import warnings

        warnings.warn(
            "Type-checking tests skipped because the plugin wasn't loaded. "
            "Run pytest with -p trio_typing._tests.datadriven to run them.",
            RuntimeWarning,
        )

else:
    from mypy import build
    from mypy.modulefinder import BuildSource
    from mypy.options import Options
    from mypy.test.data import DataDrivenTestCase, DataSuite
    from mypy.test.helpers import assert_string_arrays_equal

    class TrioTestSuite(DataSuite):
        data_prefix = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), "test-data"
        )
        files = [name for name in os.listdir(data_prefix) if name.endswith(".test")]
        native_sep = True

        def run_case(self, testcase: DataDrivenTestCase) -> None:
            src = "\n".join(testcase.input)
            options = Options()
            options.show_traceback = True
            options.python_version = sys.version_info[:2]
            options.hide_error_codes = True
            if parse_version(version("mypy")) >= parse_version("1.4"):
                options.force_union_syntax = True
                options.force_uppercase_builtins = True

            if testcase.name.endswith("_36"):
                options.python_version = (3, 6)
            else:
                options.python_version = sys.version_info[:2]
            if not testcase.name.endswith("_NoPlugin"):
                options.plugins = ["trio_typing.plugin"]
                # must specify something for config_file, else the
                # plugins don't get loaded
                options.config_file = "/dev/null"
            result = build.build(
                sources=[BuildSource("main", None, src)], options=options
            )
            assert_string_arrays_equal(
                testcase.output,
                result.errors,
                "Unexpected output from {0.file} line {0.line}".format(testcase),
            )
