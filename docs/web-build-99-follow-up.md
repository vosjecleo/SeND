# Web build 99: deferred follow-up

Reported by the owner after the 2026-09-23 hosting cutover. These are user
observations, not established root causes. The owner requested that fixes wait;
the release remains 0.9.30+99, latest only.

1. **Synced settings reset:** opening/using the web app appears to reset shared
   settings, including appearance. Prioritize investigating account-data
   hydration and writes before any performance or cosmetic follow-up. Do not
   assume this is merely a local browser-storage issue. No production account
   settings were accessed or changed during the cutover verification.
2. **Performance:** the web app feels slow and resource-heavy. Profile startup,
   initial synchronization, rendering, memory, and asset delivery separately
   before selecting a fix. Do not change sensitive timeline scrolling based
   only on this report.
3. **Password-manager autofill:** the browser login screen does not offer the
   expected password-manager filling. Check generated input semantics and
   platform-specific password-manager behavior in a later patch.

Still requiring real-device/account validation: installed iOS PWA push display,
notification-click navigation, logout/unsubscription, and encrypted-session
restoration. A healthy gateway configuration endpoint and browser startup are
not proof of those complete flows. Use a dedicated test account rather than
copying production session credentials.
