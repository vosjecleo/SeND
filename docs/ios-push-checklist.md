# iPhone/iPad Web Push checklist

Reviewed against the 0.9.37+118 PWA-only notification preview patch.
iOS uses Web Push, not ntfy. Android native
UnifiedPush setup is a separate flow. See [Android](ANDROID.md).

The automated tests verify the browser bridge, worker and gateway with simulated
push-provider delivery. They cannot prove physical iPhone delivery. Hosting needs
the gateway and exact `/_matrix/push/v1/notify` nginx route as well as the PWA.
When migrating from builds before 108, re-enable browser notifications: those
older clients used a gateway URL rejected by Synapse. Routine PWA updates do not
require clearing the session or installing an Android ntfy distributor.

1. In Safari, add `https://chat.deltie.net` to the Home Screen. Open **that app**,
   sign in, then Settings → Notifications → Enable browser notifications. Accept
   the system permission. A regular Safari tab is not equivalent on iOS.
2. Check browser notification setup: permission should be `granted`, with worker,
   subscribed, registered and homeScreen all `true`. Copy this safe report if not.
3. Tap Send test push notification. Check Notification Centre even if a banner
   doesn't appear. This test deliberately bypasses foreground suppression.
   Failure means the gateway/subscription needs attention. A successful request
   with no visible alert needs an iOS permissions/Focus/network check; it isn't
   proof of device receipt.
4. Background the PWA and lock the phone. From another account send a fresh
   message in a non-muted room. Confirm the alert, then tap it and check the room.
5. Repeat immediately after backgrounding (within 5 seconds), then after 70
   seconds. The first case exercises the old foreground-lease race. Allow for
   the short gateway queue/lease delay. Record send/receipt times and Focus state.
6. Read the room, background again and send another message. Also test with the
   PWA fully closed. Compare explicit test pushes with actual Matrix messages.
   If tests work but messages don't, investigate Matrix pusher/rules/read state.

Check iOS Settings → Notifications → SeND: Allow Notifications, Lock Screen,
Notification Centre, banners and sounds. Check Focus and Scheduled Summary.
After denying permission, adjust it in iOS Settings and enable notifications in
SeND again. Don't clear the app's storage merely to test: that loses its session.

Do not send subscription endpoints, access tokens, recovery keys or pushkeys in
a bug report. Useful fields: iOS/device/build, setup report, installation method,
foreground/background/locked state, Focus state, test result and timings.

## Declarative fallback and encrypted previews

The updated gateway sends the `web_push: 8030` envelope with a generic visible
notification and a same-origin room link. Supporting WebKit versions (iOS/iPadOS
18.4 and later) can display it if the service worker cannot run or fails. When
the worker successfully displays its notification, WebKit suppresses the fallback;
this is not intended to produce two notifications. Older browsers and installed
SeND workers continue using the retained top-level room/event identifiers.

Deployment requires updating `server/web_push.py` in the existing gateway and
restarting its service. No VAPID rotation, database reset, nginx change, client
reinstallation or new browser permission is needed. This change alone cannot fix
missing subscriptions, permission denial, Focus suppression or push-provider
delivery failures. Verify closed-app delivery on an actual iPhone after deployment.

For previews, enable **Show message content** and **Decrypt previews on this
browser** in Notifications. The latter is device-local, off by default, and
explicitly permits lock-screen content. Enable browser notifications as usual.

The main app exports up to 256 recent inbound Megolm sessions for joined rooms,
plus its homeserver access token, into a separate AES-GCM encrypted IndexedDB
snapshot. A non-extractable WebCrypto key protects records at rest; this does not
protect against same-origin XSS or a compromised browser. No identity keys,
recovery secrets, Olm ratchets or decrypted history are exported. The worker never
writes to the Matrix SDK database. It fetches one encrypted event directly from
the homeserver, then verifies/decrypts it using Vodozemac 0.10.0, the same version
as the app's crypto backend. Sender/session/room binding and a notification-only
replay index are checked. Spoilers remain hidden; edits and uncertain identities
fall back to generic text. No decrypted message is saved by this preview code.

The worker has a 3.5-second processing budget. Snapshots stop being usable after
seven days without refresh; disabling previews/notifications or signing out clears
them. The gateway still receives no Matrix access token, decryption keys or
plaintext. Keys are **not** uploaded to the gateway. The ordinary local session
is used only for authenticated ciphertext fetches to the configured homeserver.

New/rotated sessions, forwarded keys, unavailable sender identities, offline fetches
or missing keys produce a generic alert. This is not a background Matrix client:
it does not run sync, process Olm key deliveries or recover keys from backup.
Open the app to acquire fresh keys. Test with an existing encrypted conversation,
then with a new session, previews disabled, and after logout. Physical iOS testing
is still required; Chromium worker tests cannot prove APNs delivery or iOS behavior.

Apple references: [Home Screen Web Push requirements](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
and [Declarative Web Push and local decryption](https://webkit.org/blog/16535/meet-declarative-web-push/).
