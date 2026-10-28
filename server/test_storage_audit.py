import os
from pathlib import Path
import tempfile
import unittest

from storage_audit import DEFAULT_QUOTA_BYTES, inventory, read_token, validate_origin


class StorageAuditTests(unittest.TestCase):
    def test_reports_real_media_bytes_without_inventing_message_sizes(self):
        pages = {
            0: {'media': [
                {'media_id': 'photo', 'media_type': 'image/jpeg', 'media_length': 100},
                {'media_id': 'private-media-id', 'media_type': 'application/octet-stream', 'media_length': 200},
            ], 'next_token': 2},
            2: {'media': [
                {'media_id': 'gif', 'media_type': 'image/gif', 'media_length': 50},
                {'media_id': 'pending', 'media_type': None, 'media_length': None},
            ]},
        }
        result = inventory(pages.__getitem__)
        self.assertEqual(result['used_bytes'], 350)
        self.assertEqual(result['categories']['other']['bytes'], 200)
        self.assertEqual(result['categories']['gifs']['files'], 1)
        self.assertEqual(result['remaining_bytes'], DEFAULT_QUOTA_BYTES - 350)
        self.assertIsNone(result['message_storage_bytes'])
        self.assertFalse(result['quota_enforced_by_this_tool'])
        self.assertNotIn('private-media-id', str(result))  # No media IDs in output.

    def test_duplicate_or_repeated_pages_fail_instead_of_double_counting(self):
        with self.assertRaises(ValueError):
            inventory(lambda _: {'media': [], 'next_token': 0})
        with self.assertRaises(ValueError):
            inventory(lambda _: {'media': [{'media_id': 'same', 'media_length': 1}] * 2})

    def test_negative_or_malformed_lengths_fail(self):
        for size in [-1, True, '100']:
            with self.assertRaises(ValueError):
                inventory(lambda _: {'media': [{'media_id': 'id', 'media_length': size}]})

    def test_over_quota_is_reported_without_negative_remaining_space(self):
        result = inventory(lambda _: {'media': [{'media_id': 'id', 'media_length': 11}]}, 10)
        self.assertEqual(result['remaining_bytes'], 0)
        self.assertEqual(result['over_quota_bytes'], 1)

    def test_requires_secure_endpoint(self):
        self.assertEqual(validate_origin('http://127.0.0.1:8008/'), 'http://127.0.0.1:8008')
        self.assertEqual(validate_origin('https://matrix.example.org'), 'https://matrix.example.org')
        for url in ['http://matrix.example.org', 'https://user:secret@matrix.example.org', 'https://matrix.example.org?token=secret']:
            with self.assertRaises(ValueError):
                validate_origin(url)

    def test_token_requires_private_regular_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'token'
            path.write_text('private-test-token\n')
            path.chmod(0o600)
            self.assertEqual(read_token(path), 'private-test-token')
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                read_token(path)
            link = Path(directory) / 'link'
            os.symlink(path, link)
            with self.assertRaises(OSError):
                read_token(link)


if __name__ == '__main__':
    unittest.main()
