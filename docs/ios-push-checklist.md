# iPhone/iPad Web Push check — build 108

The automated tests verify the browser bridge, worker and gateway with simulated
push-provider delivery. They cannot prove physical iPhone delivery. The release
needs the updated gateway and exact `/_matrix/push/v1/notify` nginx route as well
as the new PWA client. Re-enable browser notifications after updating: older
clients used a gateway URL rejected by Synapse.

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

Apple references: [Home Screen Web Push requirements](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
and [visible notifications for every push](https://webkit.org/blog/12945/meet-web-push/).
