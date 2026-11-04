import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).parent / 'ci/package_candidate.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)

class ReleaseIdentityTests(unittest.TestCase):
    def test_tag_and_explicit_branch_identify_same_version(self):
        for ref in ('refs/tags/v0.24.0-alpha.2', 'refs/heads/codex/release-v0.24.0-alpha.2'):
            self.assertEqual(candidate.release_tag(ref, '0.24.0'), 'v0.24.0-alpha.2')
        self.assertEqual(candidate.release_tag('refs/heads/codex/editor-fix', '0.24.0'), '')
        self.assertEqual(candidate.release_tag('refs/pull/2/merge', '0.24.0'), '')
    def test_mismatched_or_malformed_release_request_fails_closed(self):
        for suffix in ('v0.23.0-alpha.1', 'v0.24.0', 'v0.24.0-alpha.1/x', 'v0.24.0-alpha.1\n'):
            with self.assertRaises(ValueError):
                candidate.release_tag('refs/heads/codex/release-' + suffix, '0.24.0')

if __name__ == '__main__':
    unittest.main()
