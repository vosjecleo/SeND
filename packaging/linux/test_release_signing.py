import base64
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_signing', ROOT/'packaging/sign-release.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class ReleaseSigningTests(unittest.TestCase):
    def test_published_public_keys_match_embedded_client_keys(self):
        trust = json.loads((ROOT/'packaging/release-trust.json').read_text())
        client = (ROOT/'lib/services/release_signatures.dart').read_text()
        for name, key in trust.items():
            self.assertRegex(client, re.escape("'" + name + "': '" + key + "'"))
            self.assertEqual(len(base64.b64decode(key)), 32)

    def test_openssl_round_trip_tamper_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            key, trust, source, signature = (directory/name for name in ('key', 'trust', 'manifest', 'signature'))
            subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(key)], check=True, capture_output=True)
            key.chmod(0o600)
            public = subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout', '-outform', 'DER'], check=True, capture_output=True).stdout[12:]
            trust.write_text(json.dumps({'fixture': base64.b64encode(public).decode()}))
            source.write_text('{"version":"0.9.42","build":135}')
            with patch.object(signing, 'TRUST_PATH', trust):
                signing.sign(source, signature, key, manifest=True)
                signing.verify(source, signature, manifest=True)
                original = source.read_bytes()
                source.write_bytes(original + b' ')
                with self.assertRaises(subprocess.CalledProcessError):
                    signing.verify(source, signature, manifest=True)
                source.write_bytes(original)
                key.chmod(0o644)
                with self.assertRaises(ValueError):
                    signing.sign(source, signature, key)


if __name__ == '__main__':
    unittest.main()
