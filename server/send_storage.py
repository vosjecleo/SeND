"""Authenticated SeND storage and profile metadata module for Synapse 1.159.

Install storage_schema.sql first. Uses Synapse authentication, not an admin token
in clients. All deletion is owner-bound and requires an expiring preview token.
Only uploaded bytes count; messages and remote/URL-preview caches do not.
"""
import hashlib
import json
import re
import secrets
import time
from collections import OrderedDict, deque

ROOT = '/_synapse/client/send/v1'
KINDS = frozenset(('images', 'videos', 'gifs', 'audio', 'other'))
SOURCES = frozenset(('upload', 'klipy', 'asset'))
MEDIA_ID = re.compile(r'^[A-Za-z0-9_-]{1,255}$')


def category(mime):
    if not isinstance(mime, str):
        return 'other'
    mime = mime.split(';', 1)[0].strip().lower()
    if mime == 'image/gif':
        return 'gifs'
    return next((kind for prefix, kind in (('image/', 'images'), ('video/', 'videos'),
                                          ('audio/', 'audio')) if mime.startswith(prefix)), 'other')


def read_body(request):
    raw = request.content.read(65537)
    if len(raw) > 65536:
        raise ValueError('Request is too large.')
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError('Expected an object.')
    return value


class Storage:
    """Database boundary kept separate from Twisted for policy tests."""
    def __init__(self, run, server_name, delete, protected, now=None):
        self.run, self.server_name = run, server_name
        self.delete, self.protected = delete, protected
        self.now = now or (lambda: int(time.time() * 1000))

    async def quota(self, owner):
        def query(txn):
            txn.execute('SELECT COALESCE((SELECT quota_bytes FROM send_storage_limits WHERE user_id=?),'
                        '(SELECT default_bytes FROM send_storage_policy WHERE id=1))', (owner,))
            return int(txn.fetchone()[0])
        return await self.run('send_storage_quota', query)

    async def usage(self, owner):
        def query(txn):
            txn.execute("SELECT COALESCE(l.kind,CASE WHEN m.media_type='image/gif' THEN 'gifs' "
                        "WHEN SUBSTR(m.media_type,1,6)='image/' THEN 'images' WHEN SUBSTR(m.media_type,1,6)='video/' "
                        "THEN 'videos' WHEN SUBSTR(m.media_type,1,6)='audio/' THEN 'audio' ELSE 'other' END),"
                        'COALESCE(SUM(m.media_length),0),COUNT(*) FROM local_media_repository m '
                        'LEFT JOIN send_storage_labels l ON l.media_id=m.media_id AND l.owner=m.user_id '
                        'WHERE m.user_id=? AND m.media_length IS NOT NULL AND m.url_cache IS NULL GROUP BY 1', (owner,))
            return {kind: {'bytes': int(size), 'files': int(count)} for kind, size, count in txn.fetchall()}
        categories = {kind: {'bytes': 0, 'files': 0} for kind in sorted(KINDS)}
        categories.update(await self.run('send_storage_usage', query))
        used, quota = sum(item['bytes'] for item in categories.values()), await self.quota(owner)
        def enforcement(txn):
            txn.execute('SELECT enforce_all OR EXISTS(SELECT 1 FROM send_storage_limits WHERE user_id=?) FROM send_storage_policy WHERE id=1', (owner,))
            return bool(txn.fetchone()[0])
        return {'version': 1, 'used_bytes': used, 'quota_bytes': quota,
                'quota_enforced': await self.run('send_storage_enforcement',enforcement),
                'remaining_bytes': max(0, quota - used), 'categories': categories,
                'message_bytes': None, 'accounting': 'original_uploads',
                'notes': 'Messages, server-generated previews, thumbnails and backups are separate.'}

    async def label(self, owner, items):
        if not isinstance(items, list) or not 1 <= len(items) <= 100:
            raise ValueError('Supply between 1 and 100 media labels.')
        checked = []
        for item in items:
            if (not isinstance(item, dict) or not isinstance(item.get('media_id'), str)
                    or not MEDIA_ID.fullmatch(item['media_id']) or item.get('source') not in SOURCES
                    or item.get('kind') not in KINDS):
                raise ValueError('Invalid media label.')
            checked.append(item)
        def write(txn):
            saved, rejected = 0, []
            for item in checked:
                txn.execute('SELECT user_id FROM local_media_repository WHERE media_id=? AND media_length IS NOT NULL', (item['media_id'],))
                record = txn.fetchone()
                if record is None or record[0] != owner:
                    rejected.append(item['media_id'])
                    continue
                txn.execute('INSERT INTO send_storage_labels(media_id,owner,kind,source,protected) VALUES (?,?,?,?,?) '
                            'ON CONFLICT(media_id) DO UPDATE SET kind=excluded.kind,source=excluded.source,'
                            'protected=(send_storage_labels.protected OR excluded.protected)',
                            (item['media_id'], owner, item['kind'], item['source'], item['source'] == 'asset'))
                saved += 1
            return {'saved': saved, 'rejected': rejected}
        return await self.run('send_storage_label', write)

    async def files(self, owner, before, kind=None, source=None):
        if type(before) is not int or not 0 < before <= self.now() + 86400000:
            raise ValueError('Invalid age cutoff.')
        if kind is not None and kind not in KINDS or source is not None and source not in SOURCES - {'asset'}:
            raise ValueError('Invalid media filter.')
        def query(txn):
            # Unlabelled historical uploads are counted, but are not bulk-pruned
            # until their purpose is known. No guessing from encrypted filenames.
            sql = ('SELECT m.media_id,m.media_length,m.created_ts,l.kind,l.source '
                   'FROM local_media_repository m JOIN send_storage_labels l ON l.media_id=m.media_id AND l.owner=m.user_id '
                   "WHERE m.user_id=? AND m.created_ts<? AND m.media_length IS NOT NULL AND m.url_cache IS NULL "
                   "AND l.protected=FALSE AND l.source<>'asset' AND m.quarantined_by IS NULL ")
            args = [owner, before]
            if kind:
                sql += 'AND l.kind=? '
                args.append(kind)
            if source:
                sql += 'AND l.source=? '
                args.append(source)
            txn.execute(sql + 'ORDER BY m.media_length DESC,m.media_id LIMIT 100', args)
            return [{'media_id': row[0], 'bytes': row[1], 'created_ts': row[2], 'kind': row[3], 'source': row[4]}
                    for row in txn.fetchall()]
        rows = await self.run('send_storage_files', query)
        safe = await self.protected([row['media_id'] for row in rows])
        return [row for row in rows if row['media_id'] not in safe]

    async def preview(self, owner, before, kind=None, source=None):
        rows = await self.files(owner, before, kind, source)
        token = secrets.token_urlsafe(32)
        digest = hashlib.sha256(token.encode()).hexdigest()
        def save(txn):
            txn.execute('DELETE FROM send_storage_prune_jobs WHERE expires<?', (self.now(),))
            txn.execute('SELECT COUNT(*) FROM send_storage_prune_jobs WHERE owner=?', (owner,))
            if txn.fetchone()[0] >= 10:
                raise ValueError('Too many open deletion previews. Try again later.')
            txn.execute('INSERT INTO send_storage_prune_jobs VALUES (?,?,?,?)',
                        (digest, owner, json.dumps([r['media_id'] for r in rows]), self.now() + 600000))
        await self.run('send_storage_preview', save)
        return {'token': token, 'files': rows, 'bytes': sum(r['bytes'] for r in rows), 'limit': 100}

    async def prune(self, owner, token, dry_run=False):
        if not isinstance(token, str) or not 32 <= len(token) <= 128:
            raise ValueError('Invalid deletion preview.')
        digest = hashlib.sha256(token.encode()).hexdigest()
        def consume(txn):
            txn.execute('DELETE FROM send_storage_prune_jobs WHERE token_hash=? AND owner=? AND expires>? RETURNING media_ids',
                        (digest, owner, self.now()))
            row = txn.fetchone()
            if row is None:
                raise ValueError('Deletion preview expired or was already used.')
            ids = json.loads(row[0])
            result = []
            for media_id in ids:
                txn.execute('SELECT m.user_id,l.protected FROM local_media_repository m '
                            'JOIN send_storage_labels l ON l.media_id=m.media_id WHERE m.media_id=? AND m.url_cache IS NULL', (media_id,))
                value = txn.fetchone()
                if value and value[0] == owner and not value[1]:
                    result.append(media_id)
            return result
        ids = await self.run('send_storage_consume_preview', consume)
        protected = await self.protected(ids)
        selected = [media_id for media_id in ids if media_id not in protected]
        if dry_run:
            return {'deleted': 0, 'requested': len(ids), 'would_delete': len(selected), 'dry_run': True}
        deleted = await self.delete(selected) if selected else []
        return {'deleted': len(deleted), 'requested': len(ids)}


class SendStorage:
    @staticmethod
    def parse_config(config):
        return dict(config or {})

    def __init__(self, config, api):
        from synapse.http.server import DirectServeJsonResource, respond_with_json
        from synapse.api.errors import SynapseError
        from synapse.types import UserID
        self.api, self._rates = api, OrderedDict()
        hs = api._hs  # Version-pinned adapter; clients never receive admin access.
        preview_users = config.get('preview_users')
        if preview_users is not None and (not isinstance(preview_users,list) or not preview_users or
                any(not isinstance(user,str) or not UserID.is_valid(user) for user in preview_users)):
            raise ValueError('preview_users must contain explicit Matrix user IDs.')
        preview_users = set(preview_users) if preview_users is not None else None
        repo, store = hs.get_media_repository(), hs.get_datastores().main

        async def protected(ids):
            if not ids:
                return set()
            # Reuse Synapse's own global/room/avatar protection rules.
            candidates = set(await store.get_local_media_ids(
                before_ts=int(time.time() * 1000) + 86400000, size_gt=0, keep_profiles=True,
                include_quarantined_media=False, include_protected_media=False))
            references = {f'mxc://{api.server_name}/{value}': value for value in ids}
            def custom_profile_assets(txn):
                result = set()
                for field in ('net.deltiecord.banner', 'net.deltiecord.voice_background'):
                    placeholders = ','.join('?' for _ in references)
                    txn.execute(f'SELECT fields->>? FROM profiles WHERE fields->>? IN ({placeholders})',
                                [field, field, *references])
                    result.update(references[row[0]] for row in txn.fetchall())
                return result
            custom = await api.run_db_interaction('send_storage_profile_assets', custom_profile_assets)
            return (set(ids) - candidates) | custom

        async def delete(ids):
            removed, _ = await repo.delete_local_media_ids(ids)
            return removed

        self.storage = Storage(api.run_db_interaction, api.server_name, delete, protected)

        if not getattr(repo, '_send_storage_guarded', False):
            original_upload = repo.create_or_update_content
            async def guarded_upload(media_type, upload_name, content, content_length, auth_user, media_id=None):
                if preview_users is not None and auth_user.to_string() not in preview_users:
                    return await original_upload(media_type,upload_name,content,content_length,auth_user,media_id=media_id)
                allocated = media_id is None
                if allocated:
                    # Know the ID before writing bytes, so a rejected database
                    # admission cannot leave an untracked file on disk.
                    reference, _ = await repo.create_media_id(auth_user)
                    media_id = reference.rsplit('/', 1)[1]
                try:
                    return await original_upload(media_type, upload_name, content, content_length, auth_user, media_id=media_id)
                except BaseException as error:
                    if allocated:
                        record = await store.get_local_media(media_id)
                        if record is not None and record.user_id == auth_user.to_string() and record.media_length is None:
                            await repo.delete_local_media_ids([media_id])
                    if getattr(getattr(error, 'diag', None), 'constraint_name', None) == 'send_storage_quota':
                        raise SynapseError(413, 'Media storage allowance exceeded. Open Server storage to free space.', errcode='M_TOO_LARGE') from None
                    raise
            repo.create_or_update_content = guarded_upload
            repo._send_storage_guarded = True

        async def allowed(user_id, size):
            if preview_users is not None and user_id not in preview_users:
                return True
            usage = await self.storage.usage(user_id)
            return not usage['quota_enforced'] or size >= 0 and usage['used_bytes'] + size <= usage['quota_bytes']
        api.register_media_repository_callbacks(is_user_allowed_to_upload_media_of_size=allowed)

        module = self
        class Resource(DirectServeJsonResource):
            isLeaf = True
            async def handle(self, request, body):
                requester = await api.get_user_by_req(request)
                owner = requester.user.to_string()
                if preview_users is not None and owner not in preview_users:
                    raise SynapseError(404,'Storage preview is not enabled for this account.')
                if not hs.is_mine(requester.user):
                    raise SynapseError(403, 'A local account is required.')
                now = time.monotonic()
                bucket = module._rates.pop(owner, None)
                if bucket is None:
                    for old, values in list(module._rates.items()):
                        if not values or values[-1] < now - 60:
                            del module._rates[old]
                    if len(module._rates) >= 2048:
                        raise SynapseError(429, 'Too many storage requests.')
                    bucket = deque()
                while bucket and bucket[0] < now - 60:
                    bucket.popleft()
                module._rates[owner] = bucket
                if len(bucket) >= 60:
                    raise SynapseError(429, 'Too many storage requests.')
                bucket.append(now)
                module._rates[owner] = bucket
                action = request.path.decode('ascii').removeprefix(ROOT + '/')
                try:
                    if action == 'usage' and request.method == b'GET':
                        value = await module.storage.usage(owner)
                        value['dry_run_pruning'] = config.get('dry_run_pruning') is True
                    elif action == 'labels' and request.method == b'POST':
                        value = await module.storage.label(owner, body.get('items'))
                    elif action == 'prune-preview' and request.method == b'POST':
                        value = await module.storage.preview(owner, body.get('before'), body.get('kind'), body.get('source'))
                    elif action == 'prune' and request.method == b'POST' and body.get('confirm') is True:
                        value = await module.storage.prune(owner, body.get('token'),dry_run=config.get('dry_run_pruning') is True)
                    elif action == 'profiles' and request.method == b'POST':
                        users = body.get('users')
                        if not isinstance(users, list) or not 1 <= len(users) <= 32 or any(not isinstance(u, str) or not UserID.is_valid(u) for u in users):
                            raise ValueError('Supply between 1 and 32 Matrix user IDs.')
                        profiles = {}
                        handler = hs.get_profile_handler()
                        for user in dict.fromkeys(users):
                            try:
                                if not hs.is_mine(UserID.from_string(user)):
                                    continue
                                await handler.check_profile_query_allowed(UserID.from_string(user), requester.user)
                                profile = await handler.get_profile(user, ignore_backoff=False)
                                profiles[user] = {k: v for k, v in profile.items() if k in (
                                    'displayname','avatar_url','net.deltiecord.banner','net.deltiecord.voice_background',
                                    'net.deltiecord.bio','net.deltiecord.pronouns','m.tz','net.deltiecord.profile_color','net.deltiecord.profile_color_secondary','net.deltiecord.voice_color')}
                            except SynapseError:
                                continue
                        value = {'profiles': profiles}
                    else:
                        raise SynapseError(404, 'Unknown SeND endpoint.')
                except (ValueError, TypeError, json.JSONDecodeError):
                    raise SynapseError(400, 'Invalid storage request. Refresh the preview and try again.')
                request.setHeader(b'Cache-Control', b'no-store')
                respond_with_json(request, 200, value, send_cors=True)
            async def _async_render_GET(self, request):
                await self.handle(request, {})
            async def _async_render_OPTIONS(self, request):
                # Browser preflight has no bearer token. It returns no account
                # data; GET/POST still authenticate through Synapse.
                respond_with_json(request, 200, {}, send_cors=True)
            async def _async_render_POST(self, request):
                try:
                    body = read_body(request)
                except (ValueError, TypeError):
                    raise SynapseError(400, 'Invalid storage request.')
                await self.handle(request, body)
        api.register_web_resource(ROOT, Resource())
