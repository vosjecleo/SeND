# Browser storage safety

SeND's browser adapter is pinned to Matrix Dart SDK 10.1.0. It keeps the SDK's
logical database API while encrypting IndexedDB records with AES-GCM and using
HMACs for lookup keys. Browser-stored, non-extractable keys unlock automatically.
This does not protect against compromised same-origin code or guarantee
protection for a copied browser profile.

## Dumps and imports

Startup and the current storage migrations do not call `exportDump()` or
`importDump()`. Those methods remain available through the SDK database API.

Database exports read all 23 collections in one read-only IndexedDB snapshot.
They do not clear the source. Imports validate collection names, types and the
schema version before staging writes, then replace the supplied collections in
one IndexedDB transaction. A failed validation, encryption preparation or commit
leaves the previous database intact.

Older SDK dumps omitted profiles and receipts. Those two missing collections
are retained when restoring the same account. A legacy dump cannot reuse them
from a different account. Current dumps include both, plus events and encryption
sessions.

The returned dump string contains plaintext access tokens, messages and
encryption material. Keep it private and encrypt any saved copy. The SDK's
higher-level `Client.exportDump()` is a session-transfer operation which still
disposes and clears its client. Do not use that wrapper as a backup command or
run duplicate imported sessions concurrently.

## Key index and migration

IndexedDB schema 1102 adds an encrypted key directory for each collection.
Room-scoped lookups use opaque HMAC partitions, not readable room IDs. Names,
counts and opaque grouping relationships remain structural metadata.

Message values and their key-directory entries commit together. The upgrade
authenticates existing rows and adds directory entries in bounded pages. It does
not rotate the browser key. Interrupted upgrades retry without deleting source
records. Missing or malformed key markers and missing keys stop opening.
Authentication failures are returned without replacing stored data.

`getAllKeys()` reads small encrypted key records instead of decrypting message
values. Room loading and cleanup use scoped queries. Global enumeration uses
512-row pages and at most 16 concurrent decryptions. The adapter's per-collection
plaintext LRU holds at most 128 records and an estimated 512 KiB. Pending
transaction changes are separate, so eviction cannot hide uncommitted writes.
These limits do not include the SDK's active room/timeline state or explicit
full-value reads and exports.

## Measurements and checks

On a physical Pixel 8 using Vanadium, 10,000 synthetic 2 KiB messages across 100
rooms gave these results:

| Operation | Before | After |
| --- | ---: | ---: |
| Write the fixture | 7,294 ms | 11,722 ms |
| Enumerate all keys | 2,397 ms | 2,031 ms |
| Look up one room's keys | Whole collection scan | 33 ms |

The old scan decrypted 20,997,890 bytes. The new global and room lookups together
decrypted 1,078,478 bytes and cached no message values. Maintaining the index
increases write work; the gain is cheaper scoped reads and lower memory use,
not faster writes.

The desktop 100,000-row check used a fresh Chromium profile for each adapter,
with the same 4 GiB memory limit and two-core CPU quota:

| Operation | Before | After |
| --- | ---: | ---: |
| Write the fixture | 21,463 ms | 50,953 ms |
| Enumerate all keys | 14,909 ms | 8,636 ms |
| Look up one room's keys | Whole collection scan | 128 ms |

The old scan decrypted 210,078,890 bytes. The new global and room lookups together
decrypted 10,885,778 bytes. Bulk writes are slower, especially at this scale;
this is a read/memory optimisation, not a general throughput improvement.

`tool/protected_web_storage_test.mjs` covers round trips, invalid and aborted
imports, legacy migration, interrupted index upgrades, missing keys, corrupted
markers, tampering and transaction isolation. It uses synthetic data only. The
probe passed on desktop Chromium and on the phone before the final marker
hardening; that additional hardening is checked separately on Chromium.

`tool/protected_web_storage_benchmark.mjs` accepts `ROWS`, `CPU_THROTTLE` and an
optional Android DevTools endpoint. Remote runs delete only their named fixture
database and fixture key. They do not inspect SeND accounts or download media.
