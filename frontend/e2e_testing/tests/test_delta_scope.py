import json
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from support import delta_scope


class DeltaScopeTests(unittest.TestCase):
    def setUp(self):
        self.previous = os.environ.get(delta_scope.SCOPE_ENV)
        os.environ[delta_scope.SCOPE_ENV] = "1"

    def tearDown(self):
        if self.previous is None:
            os.environ.pop(delta_scope.SCOPE_ENV, None)
        else:
            os.environ[delta_scope.SCOPE_ENV] = self.previous

    def test_manifest_has_exact_remaining_parent_set(self):
        result = delta_scope.summary()
        self.assertEqual(result["allowed_parent_count"], 18)
        self.assertEqual(result["excluded_parent_count"], 3)
        self.assertEqual(result["retained_parent_count"], 64)
        self.assertIn("U-WATCH.02", result["allowed_parents"])

    def test_delta_allows_a_named_gap_only(self):
        delta_scope.assert_allowed("U-WATCH.02", "FULL-DELTA-WATCH-SESSION")
        with self.assertRaises(delta_scope.DeltaScopeError):
            delta_scope.assert_allowed("U-WATCH.01", "FULL-RETAINED-WATCH-PLAYBACK")
        with self.assertRaises(delta_scope.DeltaScopeError):
            delta_scope.assert_allowed("A-CF.01", "FULL-CF-SEED")

    def test_manifest_rejects_overlap(self):
        payload = {"allowed_parents": {"U-WATCH.02": "gap"}, "excluded_parents": {"U-WATCH.02": "bad"}}
        with self.assertRaises(delta_scope.DeltaScopeError):
            delta_scope.validate(payload)

    def test_retained_child_inside_partial_parent_is_rejected(self):
        retained = json.loads((ROOT / 'coverage/retained-evidence.json').read_text(encoding='utf-8'))['cases']
        candidate = next((key, records) for key, records in retained.items()
                         if any(r.get('parent') == 'U-PLAN.03' for r in records))
        with self.assertRaises(delta_scope.DeltaScopeError):
            delta_scope.assert_allowed('U-PLAN.03', candidate[0])


if __name__ == "__main__":
    unittest.main()
