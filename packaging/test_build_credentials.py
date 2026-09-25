"""Credential guards use fake values and mocked Last.fm responses only."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'build_credentials', Path(__file__).with_name('flutter-with-credentials.py'))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class CredentialTests(unittest.TestCase):
    def test_duplicate_pair_rejected_without_network(self):
        with patch.object(build.urllib.request, 'urlopen') as request:
            with self.assertRaises(SystemExit):
                build.verify_credentials('a' * 32, 'A' * 32)
            request.assert_not_called()

    def test_valid_signed_pair(self):
        payload = io.BytesIO(json.dumps({'token': 'fake-token-value-1234'}).encode())
        with patch.object(build.urllib.request, 'urlopen', return_value=payload) as request:
            build.verify_credentials('a' * 32, 'b' * 32)
        data = build.urllib.parse.parse_qs(request.call_args.args[0].data.decode())
        self.assertEqual(data['method'], ['auth.getToken'])
        self.assertIn('api_sig', data)
        self.assertNotIn('b' * 32, str(data))

    def test_rejected_pair_withholds_response(self):
        payload = io.BytesIO(b'{"error":13,"message":"sensitive response"}')
        with patch.object(build.urllib.request, 'urlopen', return_value=payload):
            with self.assertRaises(SystemExit) as caught:
                build.verify_credentials('a' * 32, 'b' * 32)
        self.assertNotIn('sensitive response', str(caught.exception))

    def test_network_failure_stops_build_without_details(self):
        with patch.object(build.urllib.request, 'urlopen', side_effect=OSError('sensitive URL')):
            with self.assertRaises(SystemExit) as caught:
                build.verify_credentials('a' * 32, 'b' * 32)
        self.assertNotIn('sensitive URL', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
