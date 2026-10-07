# Android implementation and testing

For APK selection and installation, see [Installing SeND](../INSTALL.md#android).
This guide covers Android integration, signing, notifications and device testing.

The phone UI in `lib/ui/mobile` shares the desktop backend, models, encrypted
session store, media and RTC services.

## Navigation model

The phone shell keeps navigation, timeline, and room details as animated layers
instead of replacing routes. This preserves the selected room, bounded timeline,
scroll position, and local per-room draft while panels move on or off screen.

- Right swipe on the timeline opens Home/Space navigation.
- Left swipe on visible navigation restores the timeline.
- Tapping the room header opens details from the right. A right swipe or Back
  closes it.
- Tapping a person opens a draggable profile sheet from the bottom.
- A local left swipe on a message replies without invoking global navigation.
- Android Back closes temporary UI, details, and then the timeline in that
  order before deferring to the operating system.

## Authentication and media

Browser SSO returns via a random-port loopback callback; the return intent only
foregrounds SeND. Test cancellation, process interruption and recovery before
relying on that flow.

Android Media3 prepares videos locally. If preparation fails, the user can retry,
send the original or cancel. See the [build 116 diagnosis and device checks](build-116-video.md)
for the camera-clip cache-directory fix.

Sound pack v3 includes nine cues. DM/group invitations ring for up to 30 seconds;
joining a server voice channel does not ring.

## Signing

Release CI requires a persistent signing identity. It will fail rather than
silently produce an APK with a GitHub runner's temporary debug certificate.
Provide the keystore through the `DELTIECORD_ANDROID_KEYSTORE_BASE64`,
`DELTIECORD_ANDROID_STORE_PASSWORD`, and `DELTIECORD_ANDROID_KEY_PASSWORD`
repository secrets. `DELTIECORD_ANDROID_KEY_ALIAS` is optional because CI can
derive the first key alias from the keystore. Local release builds may
use ignored `android/key.properties` values with the equivalent fields. Never
commit a keystore or signing password.

Changing signing identities prevents an in-place Android upgrade. Builds 62 and
63 were signed by ephemeral CI debug identities, which caused the reported
"App not installed" upgrades. Users of those APKs need one uninstall before the
first persistently signed build; upgrades after that keep working. Back up the
release keystore independently before publishing that build.

## Notifications and background operation

SeND creates an Android message notification channel and preserves the
existing encrypted-preview privacy preference. Notification payloads select the
corresponding room/event when the process receives them.

Onboarding and Settings > Notifications offer three delivery choices:

- **Built-in:** SeND keeps a native HTTPS stream open to `push.deltie.net`.
  No separate app or Google Play services are needed. It shows a quiet ongoing
  notification. Allow SeND unrestricted background battery use for timely alerts.
- **UnifiedPush:** install and configure a distributor such as ntfy, then select
  it in SeND. This lets several apps share one background connection.
- **Off:** disables background delivery on this device. Reopening SeND does not
  silently turn it back on.

The choice is local to the device, not synced through Matrix. Built-in delivery
uses a random 256-bit topic capability, stored in private Android preferences.
Both transports register an `event_id_only` pusher with the Matrix gateway on
the endpoint's origin. Neither credentials nor capabilities are shipped or logged.

The built-in listener decodes bounded ntfy JSON frames and hands event IDs to
the existing local decryption worker. It does not keep a Flutter engine or a
Matrix sync loop running between pushes. It reconnects with backoff, responds to
network changes, and replays cached hints after an interruption. The replay cursor
advances after WorkManager persists the work. The server's cache retention limits
how far back it can replay; opening SeND still syncs the full missed timeline.

Android can restart the listener after process eviction, reboot or an app update.
Force-stop prevents delivery until SeND is opened again. Vendor battery policies
can also interrupt it. Logout and changing delivery method stop the listener.
Its foreground service uses Android's `specialUse` type with a declared purpose,
not a permanent `dataSync` task with a time limit.

Registration is callback-driven: SeND asks the selected distributor for
an endpoint during setup, explicit refresh, or recovery from a registration
failure, then waits for that callback before installing the Matrix pusher.
Foreground resume verifies the existing pusher without rotating its endpoint.
Endpoint-change callbacks trigger the same repair, and a network-constrained
12-hour WorkManager task provides a bounded safety net while the app stays
closed. The Notifications page reports each stage and offers a private
gateway-to-receiver test so a stopped distributor can be distinguished from a
gateway, Matrix, decryption, or notification-suppression failure.

This listener is separate from the embedded Firebase-compatible distributor,
which is not enabled in release builds.
Matrix requires a WebPush-capable gateway and VAPID configuration for that
route; silently falling back to an unconfigured embedded distributor would
leave notifications registered but undeliverable.

Release CI produces architecture-specific APKs for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`, plus an AAB. Most current physical phones should
use the smaller `arm64-v8a` APK.

Push payloads are treated as generic Matrix room/event wake-ups, never as
trusted plaintext. A short-lived foreground service protects the receiver-to-
worker hand-off, then a bounded Android worker restores SeND's local Matrix
session, synchronizes the named event and any room key, then decrypts the
notification locally. The distributor and gateway never receive decrypted
text, access tokens, or room keys. Android conversation notifications show the
latest message when collapsed and up to six recent messages when expanded;
bounded image attachments can appear in the expanded view. Failed local
resolution is recorded in Settings without leaving a generic wake-up alert.

An active MatrixRTC session may also be constrained by vendor background policy.
The in-app persistent call island is implemented, but a production Android
foreground-call service still needs broader device validation.

## Platform permissions

Internet access is always required. Notification, microphone, camera, and screen
capture permissions are requested when the corresponding feature needs them.
Screen sharing uses the WebRTC/Android MediaProjection path exposed by the
current plugin and begins only after explicit user action.

Secure Matrix credentials use `flutter_secure_storage`; the Matrix SQLite store
uses SQLCipher with a secure-storage key and verified migration of old databases.
This does not claim every cache/file is encrypted. See the
[security review](build-103-security-review.md). Media/file picking,
clipboard access, external URLs, camera/microphone capture, media playback, and
RTC continue through the existing cross-platform services and plugins.

## Real-device validation

CI proves that the APK and AAB compile, not that every Android integration works
on every device. Before a stable release, test at least Android 10 through the
current Android version on multiple vendors:

- login, encrypted session restoration, recovery, and secure-storage persistence
- DM/Space navigation, gestures, Back behavior, drafts, and orientation changes
- encrypted text/media send, receive, streaming, seeking, suspend, and resume
- notification permission, privacy, delivery, and room/event deep links
- built-in delivery with the screen off, Doze, network changes, process eviction,
  reboot, force-stop/reopen, provider changes and logout; measure idle battery use
- clipboard, file/media picker, camera and microphone permissions
- voice-room join/reconnect, mute, deafen, speaker/Bluetooth routing, and levels
- camera switching, group video, screen capture, and capture cancellation
- app backgrounding, vendor battery management, and ongoing RTC behavior

The official CI workflow is `.github/workflows/android.yml`. It pins and verifies
Flutter and Rust inputs, runs formatting, analysis, and the complete test suite,
then produces both a sideloadable APK and an AAB.

The built-in listener has a live gateway/stream transport check and unit tests.
End-to-end delivery and battery use still need physical-device testing before
release. Implementation references: [FluffyChat's push handling](https://github.com/krille-chan/fluffychat/blob/main/lib/utils/background_push.dart),
[Element's notification design](https://github.com/element-hq/element-android/blob/develop/docs/notifications.md),
[ntfy streaming API](https://docs.ntfy.sh/subscribe/api/), and
[Android foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types).
