import doctest
import unittest

import multihash
import multihash.funcs
import multihash.codecs
import multihash.multihash


def suite():
    tests = unittest.TestSuite()
    for module in [
            multihash.funcs, multihash.codecs, multihash.multihash,
            multihash]:
        tests.addTests(doctest.DocTestSuite(module))
    return tests

if __name__ == '__main__':
    unittest.main(defaultTest='suite')
