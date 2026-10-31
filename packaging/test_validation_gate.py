"""Exercise the publishing gate with synthetic GitHub runs, without network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'a' * 40


class ValidationGateTests(unittest.TestCase):
    def run_gate(self, runs, commit=COMMIT):
        with tempfile.TemporaryDirectory() as directory:
            gh = Path(directory) / 'gh'
            gh.write_text('''#!/usr/bin/env python3
import os
import sys
assert sys.argv[1:3] == ['run', 'list']
options = dict(zip(sys.argv[3::2], sys.argv[4::2]))
assert options['--repo'] == 'example/test'
assert options['--workflow'] == 'validation.yml'
assert options['--commit'] == 'a' * 40
assert options['--event'] == 'push'
assert options['--json'] == 'databaseId,headSha,status,conclusion'
print(os.environ['FIXTURE_RUNS'])
''')
            gh.chmod(0o700)
            return subprocess.run(
                ['bash', str(ROOT / 'packaging/await-validation.sh'), commit],
                env={**os.environ, 'PATH': directory + os.pathsep + os.environ['PATH'],
                     'FIXTURE_RUNS': json.dumps(runs), 'SEND_VALIDATION_ATTEMPTS': '1',
                     'GITHUB_REPOSITORY': 'example/test'},
                capture_output=True, text=True, timeout=5,
            )

    def run_record(self, **fields):
        return {'databaseId': 1, 'headSha': COMMIT, 'status': 'completed',
                'conclusion': 'success', **fields}

    def test_accepts_only_success_for_the_requested_commit(self):
        self.assertEqual(self.run_gate([self.run_record()]).returncode, 0)
        self.assertNotEqual(self.run_gate([self.run_record(headSha='b' * 40)]).returncode, 0)

    def test_missing_pending_cancelled_skipped_or_failed_validation_cannot_publish(self):
        for runs in ([], [self.run_record(status='in_progress')],
                     *[[self.run_record(conclusion=result)] for result in ('cancelled', 'skipped', 'failure')]):
            with self.subTest(runs=runs):
                self.assertNotEqual(self.run_gate(runs).returncode, 0)

    def test_old_success_cannot_mask_a_new_failed_or_pending_rerun(self):
        for update in ({'conclusion': 'failure'}, {'status': 'in_progress'}):
            with self.subTest(update=update):
                self.assertNotEqual(self.run_gate([
                    self.run_record(), self.run_record(databaseId=2, **update),
                ]).returncode, 0)

    def test_invalid_commit_is_rejected(self):
        self.assertEqual(self.run_gate([], commit='main; exit 0').returncode, 2)
