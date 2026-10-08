import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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
            self.assertIn('ffmpeg', (root / 'helpers/Dockerfile').read_text())
            self.assertIn('hosting_config.py', [p.name for p in (root / 'helpers').iterdir()])
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
