# Build 103 security and validation handoff

This review records source/host validation, not a completed native-device
security certification. Subsequent CI-only compilation and latest publication
were authorized on 2026-09-24; the physical-device checks below remain outstanding.

Final host validation: `flutter analyze` reports no issues; `flutter test`
passes 303 tests with one existing skip. Dart formatting and `git diff --check`
also pass. These checks do not substitute for the native release gates below.

## Findings and changes

1. **High, local-access prerequisite:** Android's Matrix SQLite store was
   plaintext. `encrypted_android_database.dart` now uses SQLCipher, a random
   key in Flutter secure storage, and an atomic verified export of an existing
   database. Missing keys and failed migrations fail closed without resetting
   the source. Plugin exceptions are redacted because SQL arguments can contain
   key material. `matrix_client_factory_native.dart` uses this opener for both
   foreground and background-worker Matrix clients.
2. **High, malicious encrypted attachment:** ranged encrypted video decoding
   previously could not authenticate the complete ciphertext against its
   declared SHA-256. `matrix_media.dart` requires the Matrix attachment hash;
   `media_range_proxy.dart` downloads bounded ciphertext, checks it, then permits
   decryption. Tampered data never reaches the decoder. Downloads have a 512 MiB
   per-item/aggregate registration bound, idle timeout and total time bound.
   Seeking reuses the verified encrypted cache. This deliberately means waiting
   for a full download before playing encrypted video, not unauthenticated
   early streaming. Unencrypted media has no comparable Matrix declared hash.
3. **Medium, deceptive formatted links:** visible HTML link labels could hide
   their destination. `matrix_html_text.dart` now requires confirmation showing
   the complete URL in left-to-right text. Plain visible URLs retain their
   established behavior. This is destination disclosure, not a phishing verdict.

## Existing safeguards left in place

- Android cloud/device backups remain disabled/excluded by existing manifest
  and extraction rules. Notification-worker and UnifiedPush architecture is
  not replaced by this patch.
- Matrix E2EE, password authentication, cross-signing and key backup remain SDK
  responsibilities. SQLCipher supplies database encryption; no custom cipher.
- Existing private temporary media cache and cleanup remain the owner of cached
  ciphertext. No persistent decrypted-video copy is introduced.
- Existing endpoint/URL policies and secure-secret storage are not relaxed.
- Useful lifecycle and security comments are retained; no broad storage rewrite.

## Validation and remaining risks

- Automated tests cover missing database key, unavailable SQLCipher plugin
  preserving the source, tampered/valid encrypted media and cache reuse, link
  confirmation, formatting, receipt frontiers, usage counting, composer sizing,
  logout confirmation, colour-picker dismissal and repeated resume/theme edits.
- **Before stable promotion:** test Android migration on a disposable restored
  database, cold start, background notification worker, process interruption
  during export, low disk space, logout and re-login. Real SQLCipher and Android
  Keystore integration cannot be proven by host widget tests.
- Migration removes the old logical plaintext file, but cannot promise forensic
  erasure of old flash blocks. Encryption also does not protect an unlocked,
  compromised/rooted running device or malicious accessibility software.
- Desktop SQLite and some auxiliary local stores/drafts retain existing OS
  permissions rather than gaining database encryption. Browser IndexedDB is not
  encrypted by this Android change. Do not describe every local store as encrypted.
- Favourites/usage retain the existing device-level preference store; they are
  not a new account-isolated storage system. Explicit later SDK retries are not
  included in usage statistics; this avoids double-counting normal retries.
- Physical Android freeze/resume, IME edits, high text scale, RTL inline receipts,
  media albums and group receipt boundaries need visual/runtime checks.
- Other homeserver password UI-auth types, large encrypted videos, and
  certificate/network failures need runtime validation. iOS/PWA-specific fixes
  and tests are deferred at the user's request.

## Reference implementations inspected

- FluffyChat: `lib/pages/settings_password/settings_password.dart`,
  `lib/utils/markdown_context_builder.dart`, and database builder/cipher helpers
  under `lib/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/`.
  Used as lifecycle/API references, not copied wholesale.
- Locked matrix-dart-sdk event/receipt and password APIs; SQLCipher plugin 3.4.1
  API and native dependency declarations. No Matrix SDK upgrade in this patch.
