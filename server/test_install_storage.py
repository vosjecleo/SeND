import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess

spec = importlib.util.spec_from_file_location('storage_installer', Path(__file__).with_name('install_storage.py'))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerCompatibilityTests(unittest.TestCase):
    def test_selects_legacy_compose_when_plugin_is_absent(self):
        def run(command, **kwargs):
            return subprocess.CompletedProcess(command, 1 if command[:2] == ['docker', 'compose'] else 0)
        with patch.object(installer.subprocess, 'run', side_effect=run):
            self.assertEqual(installer.compose_command(), ['docker-compose'])

    def test_prefers_working_compose_plugin(self):
        with patch.object(installer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)):
            self.assertEqual(installer.compose_command(), ['docker', 'compose'])

    def test_old_compose_does_not_receive_unsupported_pull_flag(self):
        command = installer.restart_arguments(['docker-compose'], '--no-build --force-recreate --pull')
        self.assertNotIn('--pull', command)
        self.assertIn('--no-build', command)
        self.assertIn('--force-recreate', command)
        self.assertIn('--no-deps', command)

    def test_new_compose_disables_pulling_explicitly(self):
        command = installer.restart_arguments(['docker', 'compose'], '--pull policy (always|missing|never)')
        self.assertEqual(command[-2:], ['--pull', 'never'])

    def test_module_permissions_ignore_restrictive_umask_and_repair_existing_dir(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary) / 'send_modules'
            previous = os.umask(0o077)
            try:
                installer.module_directory(folder)
                self.assertEqual(folder.stat().st_mode & 0o777, 0o755)
                folder.chmod(0o700)
                installer.module_directory(folder)
                self.assertEqual(folder.stat().st_mode & 0o777, 0o755)
            finally:
                os.umask(previous)


if __name__ == '__main__':
    unittest.main()
