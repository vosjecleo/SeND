import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('deploy_storage', Path(__file__).with_name('deploy_storage.py'))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / 'synapse'
        self.target = self.data / 'send_modules' / 'send_storage.py'
        self.target.parent.mkdir(parents=True)
        self.old, self.new = b'old = True\n', b'new = True\n'
        self.target.write_bytes(self.old)
        (self.root / 'send_storage.py').write_bytes(self.new)
        self.inspection = {'Id': 'container', 'Image': 'image'}

    def run_main(self, arguments, installed=None, health=None, restore=None):
        real_open = os.open
        def opened(path, *args, **kwargs):
            descriptor = real_open(path, *args, **kwargs)
            if str(path).endswith('.send-storage-deploy.lock'):
                self.addCleanup(os.close, descriptor)
            return descriptor
        with patch.object(deploy, '__file__', str(self.root / 'deploy_storage.py')), \
             patch.object(deploy, 'KNOWN_PREVIEW_MODULES', {deploy.digest(self.old)}), \
             patch.object(deploy, 'inspect', return_value=(self.inspection, self.data)), \
             patch.object(deploy, 'installed', side_effect=installed or [self.old, self.new]), \
             patch.object(deploy, 'healthy', side_effect=health), \
             patch.object(deploy, 'execute', return_value=b'1.159.0') as execute, \
             patch.object(deploy.os, 'geteuid', return_value=0), \
             patch.object(deploy.os, 'open', side_effect=opened), \
             patch('sys.argv', ['deploy_storage.py', *arguments]):
            if restore is None:
                deploy.main()
            else:
                with patch.object(deploy, 'restore', restore):
                    deploy.main()
            return execute

    def test_default_is_read_only(self):
        execute = self.run_main([])
        self.assertEqual(self.target.read_bytes(), self.old)
        self.assertEqual(list(self.data.iterdir()), [self.target.parent])
        self.assertFalse(any('restart' in call.args[0] for call in execute.call_args_list))

    def test_apply_backs_up_and_restarts_only_synapse(self):
        execute = self.run_main(['--apply'])
        self.assertEqual(self.target.read_bytes(), self.new)
        backup = next(self.data.glob('send-storage-rollback-*'))
        self.assertEqual((backup / 'send_storage.py').read_bytes(), self.old)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o644)
        commands = [call.args[0] for call in execute.call_args_list]
        self.assertEqual(commands[-1], ['docker', 'restart', 'matrix-synapse'])
        self.assertFalse(any('compose' in command or 'psql' in command for command in commands))

    def test_health_failure_attempts_rollback(self):
        from unittest.mock import Mock
        restore = Mock()
        with self.assertRaisesRegex(RuntimeError, 'original module restored'):
            self.run_main(['--apply'], health=[None, RuntimeError('unhealthy')], restore=restore)
        restore.assert_called_once()

    def test_already_installed_never_restarts(self):
        execute = self.run_main(['--apply'], installed=[self.new])
        self.assertFalse(any('restart' in call.args[0] for call in execute.call_args_list))

    def test_unknown_local_changes_are_preserved(self):
        with self.assertRaisesRegex(RuntimeError, 'local changes'):
            self.run_main(['--apply'], installed=[b'custom'])
        self.assertEqual(self.target.read_bytes(), self.old)

    def test_restore_checks_backup_before_writing(self):
        backup = self.root / 'backup'
        backup.mkdir(mode=0o700)
        (backup / 'send_storage.py').write_bytes(self.old)
        (backup / 'manifest.json').write_text(json.dumps({
            'container': 'container', 'image': 'image', 'target': str(self.target),
            'sha256': deploy.digest(self.old), 'mode': 0o644}))
        original_stat = Path.stat
        def root_owned(path, *args, **kwargs):
            value = original_stat(path, *args, **kwargs)
            if path == backup:
                fields = list(value)
                fields[4] = 0
                return os.stat_result(fields)
            return value
        self.target.write_bytes(self.new)
        with patch.object(Path, 'stat', root_owned), patch.object(deploy, 'execute'), \
             patch.object(deploy, 'healthy'), patch.object(deploy, 'installed', return_value=self.old):
            deploy.restore('matrix-synapse', self.target, backup, self.inspection)
            self.assertEqual(self.target.read_bytes(), self.old)
            self.target.write_bytes(self.new)
            (backup / 'send_storage.py').write_bytes(b'tampered')
            with self.assertRaisesRegex(RuntimeError, 'does not match'):
                deploy.restore('matrix-synapse', self.target, backup, self.inspection)
            self.assertEqual(self.target.read_bytes(), self.new)


if __name__ == '__main__':
    unittest.main()
