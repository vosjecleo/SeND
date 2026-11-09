import json
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, MagicMock

import hosting_config
import install


class InstallerTests(unittest.TestCase):
    def config(self):
        return {'server': 'example.org', 'matrix': 'matrix.example.org',
                'app': 'chat.example.org', 'rtc': 'rtc.example.org',
                'turn': 'turn.example.org', 'push': 'push.example.org',
                'email': 'admin@example.org', 'ip': '93.184.216.34',
                'subnet': '172.29.125.0/24'}

    def test_stack_and_private_credentials(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'stack'
            install.generate(root, self.config(), {'telegram-token': 'test-token', 'klipy-key': 'test-key'})
            compose = json.loads((root / 'compose.yaml').read_text())
            self.assertEqual(len(compose['services']), 9)
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)
            for name in ('homeserver.yaml', 'compose.yaml', 'secrets/telegram-token'):
                self.assertEqual((root / name).stat().st_mode & 0o777, 0o600)
            self.assertNotIn('test-token', (root / 'compose.yaml').read_text())
            for name in ('postgres', 'synapse', 'media', 'web-push', 'jwt'):
                self.assertNotIn('ports', compose['services'][name])
            push = compose['services']['web-push']['environment']
            self.assertEqual(json.loads(push['WEB_PUSH_ISSUERS']), {'example.org': 'https://matrix.example.org'})
            synapse = json.loads((root / 'homeserver.yaml').read_text())
            self.assertFalse(synapse['enable_registration'])
            self.assertFalse(synapse['url_preview_enabled'])
            self.assertEqual(synapse['max_upload_size'], '512M')
            self.assertEqual(synapse['max_event_delay_duration'], '24h')
            self.assertTrue(synapse['experimental_features']['msc4133_enabled'])
            self.assertFalse(json.loads((root / 'livekit.yaml').read_text())['room']['auto_create'])
            self.assertIn('max_size 536870912', (root / 'Caddyfile').read_text())
            self.assertEqual((root / '.env').read_text(), 'COMPOSE_PROJECT_NAME=send\n')
            self.assertNotIn('name', compose)
            self.assertIn('matrix.example.org', compose['services']['caddy']['networks']['send']['aliases'])
            self.assertIn('healthcheck', compose['services']['media'])
            self.assertIn('healthcheck', compose['services']['web-push'])
            self.assertEqual(push['WEB_PUSH_QUEUE'], '1')
            defines = json.loads((root / 'client-defines.json').read_text())
            self.assertEqual(defines['SUNUP_GATEWAY_URL'], 'https://chat.example.org/_matrix/push/v1/notify')
            self.assertNotIn('test-key', (root / 'client-defines.json').read_text())
            bundle = json.loads((root / 'setup-manifest.json').read_text())
            self.assertEqual(bundle['upload_bytes'], 512 * 1024 * 1024)
            self.assertEqual(bundle['default_account_bytes'], 12 * 1024 ** 3)
            self.assertEqual(bundle['send_version'], install.source_version())
            for filename, digest in bundle['files'].items():
                self.assertEqual(hashlib.sha256((root / filename).read_bytes()).hexdigest(), digest)
            for filename in ('web_push.py', 'web_preview.py', 'giphy_proxy.py', 'hosting_config.py'):
                self.assertEqual((root / 'helpers' / filename).read_bytes(), (install.SOURCE / filename).read_bytes())
            self.assertIn('ffmpeg', (root / 'helpers/Dockerfile').read_text())
            self.assertIn('hosting_config.py', [p.name for p in (root / 'helpers').iterdir()])
            for name in ('install_storage.py', 'send_storage.py', 'storage_schema.sql'):
                self.assertTrue((root / 'storage' / name).is_file())
            with self.assertRaises(ValueError):
                install.generate(root, self.config(), {})
            self.assertEqual(synapse, json.loads((root / 'homeserver.yaml').read_text()))

    def test_rejects_host_injection_and_private_ip(self):
        for value in ('example.org\nrespond 200', 'https://example.org', '../etc', 'x;sh', ''):
            with self.assertRaises(ValueError):
                install.domain(value)
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                install.generate(Path(temporary) / 'new', {**self.config(), 'ip': '127.0.0.1'}, {})
            self.assertFalse((Path(temporary) / 'new').exists())
            with self.assertRaises(ValueError):
                install.generate(Path(temporary) / 'new', self.config(), {'../escape': 'secret'})
            self.assertFalse((Path(temporary) / 'new').exists())

    def test_public_directory_permissions_survive_restrictive_umask(self):
        with tempfile.TemporaryDirectory() as temporary:
            before = os.umask(0o077)
            try:
                root = Path(temporary) / 'stack'
                install.generate(root, self.config(), {})
            finally:
                os.umask(before)
            self.assertEqual((root / 'discovery').stat().st_mode & 0o777, 0o755)
            self.assertEqual((root / 'discovery/client.json').stat().st_mode & 0o777, 0o644)
            self.assertEqual((root / 'homeserver.yaml').stat().st_mode & 0o777, 0o600)

    def test_legacy_startup_waits_for_health_without_new_compose_flags(self):
        command = ['docker-compose']
        def output(args, **kwargs):
            if args[-2:] == ['up', '--help']:
                return '--no-build'
            if args[-2:] == ['config', '--services']:
                return 'media\nweb-push\n'
            if args[-3:] == ['ps', '--all', '-q']:
                return 'one\ntwo\n'
            return '\n'.join(json.dumps({'Status': 'running', 'Health': {'Status': 'healthy'}}) for _ in range(2))
        with patch('install.subprocess.check_output', side_effect=output), patch('install.subprocess.run') as run:
            install.start_stack(command)
        run.assert_called_once_with(['docker-compose', 'up', '-d', '--no-build'], check=True)

    def test_plugin_startup_keeps_its_health_wait_and_disables_builds(self):
        with patch('install.subprocess.check_output', return_value='--wait --wait-timeout'), patch('install.subprocess.run') as run:
            install.start_stack(['docker', 'compose'])
        run.assert_called_once_with(['docker', 'compose', 'up', '-d', '--no-build', '--wait', '--wait-timeout', '180'], check=True)

    def test_legacy_startup_fails_for_unhealthy_or_exited_services(self):
        for states in [[{'Status': 'running', 'Health': {'Status': 'unhealthy'}}],
                       [{'Status': 'exited'}]]:
            with patch('install.subprocess.check_output', side_effect=[
                    '--no-build', 'media\n', 'one\n', '\n'.join(map(json.dumps, states))]), patch('install.subprocess.run'):
                with self.assertRaisesRegex(ValueError, 'failed its startup check'):
                    install.start_stack(['docker-compose'])

    def test_public_checks_use_no_account_or_provider_requests(self):
        config = self.config()
        values = {
            'https://matrix.example.org/_matrix/client/versions': {'versions': ['v1.13']},
            'https://example.org/.well-known/matrix/client': {
                'm.homeserver': {'base_url': 'https://matrix.example.org'},
                'org.matrix.msc4143.rtc_foci': [{'livekit_service_url': 'https://rtc.example.org/jwt'}]},
            'https://example.org/.well-known/matrix/server': {'m.server': 'matrix.example.org:443'},
            'https://chat.example.org/api/servers/health': {'ok': True},
            'https://chat.example.org/api/push/config': {'public_key': 'public-test-key'},
        }
        def fetch(url, **kwargs):
            if url.endswith('/preview?kind=invalid'):
                raise install.urllib.error.HTTPError(url, 400, '', {}, None)
            if url.endswith('/usage'):
                raise install.urllib.error.HTTPError(url, 401, '', {}, None)
            response = MagicMock(status=200)
            response.read.return_value = json.dumps(values[url]).encode()
            response.__enter__.return_value = response
            return response
        with patch('install.urllib.request.urlopen', side_effect=fetch) as opened:
            install.check_endpoints(config, require_storage=True)
        self.assertEqual(opened.call_count, 7)

    def test_legacy_startup_does_not_ignore_a_missing_container(self):
        with patch('install.subprocess.check_output', side_effect=[
                '--no-build', 'media\nweb-push\n', 'one\n', json.dumps({'Status': 'running'})]), \
                patch('install.subprocess.run'), patch('install.time.monotonic', side_effect=[0, 1, 181]), \
                patch('install.time.sleep'):
            with self.assertRaisesRegex(ValueError, 'did not become ready'):
                install.start_stack(['docker-compose'])

    def test_web_update_mode_does_not_regenerate_or_start_server_services(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'stack'
            install.generate(root, self.config(), {})
            before = (root / 'homeserver.yaml').read_bytes()
            with patch('install.sys.argv', ['install.py', '--deploy-web', str(root),
                       '--archive', 'web.tar.gz', '--manifest', 'releases.json']), \
                    patch('install.install_web') as deploy, patch('install.compose_command') as compose:
                install.main()
            deploy.assert_called_once_with(root, Path('web.tar.gz'), manifest=Path('releases.json'), signature=None)
            compose.assert_not_called()
            self.assertEqual((root / 'homeserver.yaml').read_bytes(), before)

    def test_issuer_configuration_fails_closed(self):
        with patch.dict(os.environ, {'WEB_PUSH_ISSUERS': '{}'}):
            with self.assertRaises(ValueError):
                hosting_config.openid_issuers()
        with patch.dict(os.environ, {'WEB_PUSH_ISSUERS': '{"example.org":"https://matrix.example.org"}'}):
            self.assertEqual(hosting_config.openid_issuers(), {'example.org': 'https://matrix.example.org'})
        for url in ('http://example.org', 'https://user:pass@example.org', 'https://example.org/path', 'https://example.org?x=1'):
            with self.assertRaises(ValueError):
                hosting_config.https_origin(url)

    def test_checksum_rejects_archive_before_deployment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'SeND-0.9.38+125-web.tar.gz'
            archive.write_bytes(b'not an archive')
            with patch('install.subprocess.run') as run:
                with self.assertRaises(ValueError):
                    install.install_web(root, archive, '0' * 64)
                run.assert_not_called()

    def signed_web_fixture(self, temporary):
        root = Path(temporary) / 'stack'
        install.generate(root, self.config(), {})
        archive = Path(temporary) / 'SeND-0.9.42+139-web.tar.gz'
        archive.write_bytes(b'web archive fixture')
        key = Path(temporary) / 'test-only.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(key)],
                       check=True, capture_output=True)
        key.chmod(0o600)
        public = subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'],
                                check=True, capture_output=True).stdout[-32:]
        (root / 'release-trust.json').write_text(json.dumps({'test': base64.b64encode(public).decode()}))
        manifest = Path(temporary) / 'releases.json'
        manifest.write_text(json.dumps({'platforms': {'web': {'latest': [{
            'name': archive.name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}]}}}))
        signature = Path(str(manifest) + '.sig')
        spec = importlib.util.spec_from_file_location('test_release_signer', root / 'verify-release.py')
        signer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(signer)
        signer.sign(manifest, signature, key, manifest=True)
        return root, archive, manifest, signature

    def test_signed_manifest_is_verified_before_deployment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, archive, manifest, _ = self.signed_web_fixture(temporary)
            real_run = subprocess.run
            calls = []
            def execute(command, **kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, 0) if command[1].endswith('deploy-web.py') else real_run(command, **kwargs)
            with patch('install.subprocess.run', side_effect=execute):
                install.install_web(root, archive, manifest=manifest)
            self.assertEqual([Path(command[1]).name for command in calls], ['verify-release.py', 'deploy-web.py'])
            self.assertEqual(calls[-1][-1], '0.9.42+139')

    def test_tampered_manifest_or_archive_never_reaches_deployment(self):
        for target in ('manifest', 'archive'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root, archive, manifest, _ = self.signed_web_fixture(temporary)
                path = manifest if target == 'manifest' else archive
                path.write_bytes(path.read_bytes() + b' ')
                real_run = subprocess.run
                deployed = []
                def execute(command, **kwargs):
                    if command[1].endswith('deploy-web.py'):
                        deployed.append(command)
                    return real_run(command, **kwargs)
                with patch('install.subprocess.run', side_effect=execute):
                    with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                        install.install_web(root, archive, manifest=manifest)
                self.assertEqual(deployed, [])

    def test_oidc_paths_and_optional_mail(self):
        self.assertEqual(install.issuer_url('https://sso.example.org/realms/chat/'),
                         'https://sso.example.org/realms/chat')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'stack'
            install.generate(root, {**self.config(), 'oidc': 'https://sso.example.org/realms/chat',
                'oidc_client': 'send', 'smtp_host': 'smtp.example.org', 'smtp_user': 'send'},
                {'oidc-secret': 'oidc-test', 'smtp-password': 'mail-test'})
            config = json.loads((root / 'homeserver.yaml').read_text())
            self.assertTrue(config['email']['require_transport_security'])
            self.assertEqual(config['oidc_providers'][0]['client_secret'], 'oidc-test')


if __name__ == '__main__':
    unittest.main()
