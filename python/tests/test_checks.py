"""Semantic guards on the public Lean projection fixture."""

import unittest

from cedar_poo_testing.checks import _projection


class ProjectionTests(unittest.TestCase):
    def test_requires_root_to_start_a_two_hop_lineage(self) -> None:
        root = {"mandateId": "root"}
        child = {"mandateId": "child"}
        _projection({"mandate": root, "offer": {}, "lineage": [root, child]})
        with self.assertRaises(ValueError):
            _projection({"mandate": root, "offer": {}, "lineage": [child, root]})

    def test_rejects_derived_verification_in_any_claim(self) -> None:
        root = {"mandateId": "root"}
        child = {"mandateId": "child", "verified": True}
        with self.assertRaises(ValueError):
            _projection({"mandate": root, "offer": {}, "lineage": [root, child]})


if __name__ == "__main__":
    unittest.main()
