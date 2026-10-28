import asyncio
import io
import sqlite3
import unittest

from send_storage import Storage, category, read_body


class StorageTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.executescript('''
          CREATE TABLE local_media_repository(media_id TEXT PRIMARY KEY,user_id TEXT,media_length INTEGER,
              media_type TEXT,created_ts INTEGER,url_cache TEXT,quarantined_by TEXT);
          CREATE TABLE send_storage_policy(id INTEGER PRIMARY KEY,default_bytes INTEGER,enforce_all BOOLEAN);
          INSERT INTO send_storage_policy VALUES(1,12884901888,TRUE);
          CREATE TABLE send_storage_limits(user_id TEXT PRIMARY KEY,quota_bytes INTEGER);
          CREATE TABLE send_storage_labels(media_id TEXT PRIMARY KEY,owner TEXT,kind TEXT,source TEXT,protected BOOLEAN);
          CREATE TABLE send_storage_prune_jobs(token_hash TEXT PRIMARY KEY,owner TEXT,media_ids TEXT,expires INTEGER);
        ''')
        self.now = 1000000
        self.protected = set()
        self.deleted = []
        async def run(_, callback):
            with self.db:
                return callback(self.db.cursor())
        async def protected(ids):
            return set(ids) & self.protected
        async def delete(ids):
            self.deleted.extend(ids)
            for value in ids:
                self.db.execute('DELETE FROM local_media_repository WHERE media_id=?', (value,))
            return ids
        self.store = Storage(run, 'example.org', delete, protected, now=lambda: self.now)
        self.add('mine', '@a:example.org', 80)
        self.add('other', '@b:example.org', 700)
    async def asyncTearDown(self):
        self.db.close()
    def add(self, id, owner, size, mime='application/octet-stream', cache=None):
        self.db.execute('INSERT INTO local_media_repository VALUES(?,?,?,?,?,?,NULL)',
                        (id, owner, size, mime, 10, cache))
        self.db.commit()
    async def label(self, id='mine', kind='videos', source='upload', owner='@a:example.org'):
        await self.store.label(owner, [{'media_id': id, 'kind': kind, 'source': source}])
    async def test_usage_is_owner_scoped_and_encrypted_unknown_is_other(self):
        self.add('preview', '@a:example.org', 100, 'image/jpeg', 'https://example.org')
        usage = await self.store.usage('@a:example.org')
        self.assertEqual(usage['used_bytes'], 80)
        self.assertEqual(usage['quota_bytes'], 12 * 1024**3)
        self.assertEqual(usage['categories']['other']['bytes'], 80)
        self.assertIsNone(usage['message_bytes'])
        await self.label()
        self.assertEqual((await self.store.usage('@a:example.org'))['categories']['videos']['bytes'], 80)
    async def test_preview_does_not_enforce_unset_limits(self):
        self.assertTrue((await self.store.usage('@a:example.org'))['quota_enforced'])
        self.db.execute('UPDATE send_storage_policy SET enforce_all=FALSE')
        self.assertFalse((await self.store.usage('@a:example.org'))['quota_enforced'])
        self.db.execute("INSERT INTO send_storage_limits VALUES('@a:example.org',1000)")
        self.assertTrue((await self.store.usage('@a:example.org'))['quota_enforced'])
        self.assertFalse((await self.store.usage('@b:example.org'))['quota_enforced'])
    async def test_dry_run_consumes_ticket_without_deleting_media(self):
        await self.label()
        preview = await self.store.preview('@a:example.org', 100, 'videos')
        result = await self.store.prune('@a:example.org', preview['token'], dry_run=True)
        self.assertEqual(result['deleted'], 0)
        self.assertEqual(result['would_delete'], 1)
        self.assertTrue(result['dry_run'])
        self.assertEqual(self.deleted, [])
        self.assertEqual((await self.store.usage('@a:example.org'))['used_bytes'], 80)
        with self.assertRaises(ValueError):
            await self.store.prune('@a:example.org', preview['token'])
    async def test_cannot_label_or_delete_another_owners_upload(self):
        response = await self.store.label('@a:example.org', [{'media_id': 'other', 'kind': 'videos', 'source': 'upload'}])
        self.assertEqual(response, {'saved': 0, 'rejected': ['other']})
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM send_storage_labels').fetchone()[0], 0)
        await self.label()
        preview = await self.store.preview('@a:example.org', 100, 'videos')
        with self.assertRaises(ValueError):
            await self.store.prune('@b:example.org', preview['token'])
        self.assertEqual(self.deleted, [])
        result = await self.store.prune('@a:example.org', preview['token'])
        self.assertEqual(result['deleted'], 1)
        self.assertEqual(self.deleted, ['mine'])
        with self.assertRaises(ValueError):
            await self.store.prune('@a:example.org', preview['token'])
    async def test_asset_protection_cannot_be_removed_by_relabel(self):
        await self.label(source='asset')
        await self.label(source='upload')
        self.assertEqual((await self.store.preview('@a:example.org', 100))['files'], [])
    async def test_protection_and_ownership_are_rechecked_after_preview(self):
        await self.label()
        preview = await self.store.preview('@a:example.org', 100)
        self.protected.add('mine')
        self.assertEqual((await self.store.prune('@a:example.org', preview['token']))['deleted'], 0)
        self.assertEqual(self.deleted, [])
    async def test_expired_preview_does_not_delete(self):
        await self.label()
        preview = await self.store.preview('@a:example.org', 100)
        self.now += 600001
        with self.assertRaises(ValueError):
            await self.store.prune('@a:example.org', preview['token'])
        self.assertEqual(self.deleted, [])
    async def test_klipy_filter_does_not_select_other_uploads(self):
        await self.label(kind='gifs', source='klipy')
        self.add('upload', '@a:example.org', 90)
        await self.label('upload', kind='gifs')
        preview = await self.store.preview('@a:example.org', 100, 'gifs', 'klipy')
        self.assertEqual([r['media_id'] for r in preview['files']], ['mine'])
    async def test_invalid_filters_and_labels_are_rejected(self):
        for before in [True, -1, '123', 10**15]:
            with self.assertRaises(ValueError):
                await self.store.preview('@a:example.org', before)
        with self.assertRaises(ValueError):
            await self.label('../mine')
        self.assertEqual(category('image/gif'), 'gifs')
        self.assertEqual(category(None), 'other')
        request = type('Request', (), {'content': io.BytesIO(b'x' * 65537)})()
        with self.assertRaises(ValueError):
            read_body(request)


if __name__ == '__main__':
    unittest.main()
