# SeND 0.9.35+109 — independent activity slots and PWA animation

## Activity ownership

Each Matrix device writes only `net.deltiecord.activity.device.<sha256-device-id>`.
It never reads/modifies/writes a shared device map, avoiding lost updates between
simultaneous publishers. A record has separate `slots.program`, `slots.music`,
and `lastfm_recent`; game and generic program deliberately share one slot.
Heartbeat and two-minute expiry remain; logout/opt-out deletes only that
device's field. Abandoned records expire on readers (their small profile fields
may remain on the homeserver until that device clears them).

Readers fetch the complete profile on the existing bounded schedule and combine
up to 64 unexpired contributions deterministically. Newest program wins; native
music beats Last.fm now-playing; newest completed scrobble wins. Ties use stable
field order. No process paths, program rules, credentials or raw device IDs are
published. Full records remain public profile metadata, not encrypted messages.
Offline/invisible SeND views suppress all three slots. Expiry does not erase data
another client has already retained.

The account's own profile reads other-device contributions too. Local publication
and remote presentation are distinct: disabling sharing on a phone does not hide
a game its desktop is still sharing. Detection/sharing/Last.fm publishing controls
remain device-local and are labelled accordingly. Other clients cannot discover
new activity slots unless they implement this extension. Build 109 can read the
old `net.deltiecord.activity` record during migration; build 108 cannot aggregate
the new device-owned fields, so update viewing clients together.

## UI and WebKit

Profiles show both live slots and a separate Last.fm footer. DM/member compact
status rows keep one primary label (program first, otherwise music). The online
dot now scales with the profile avatar, from 14 to 20 logical pixels including
its outline, maintaining the 45-degree anchor.

Mobile profiles use a higher sheet and fixed clipped frame. Only the content
scrolls, and downward scrolling from inside the content no longer dismisses the
sheet. Widget coverage includes activity-scope inheritance across the modal route.

Last.fm retains a still-fresh cached response across quick resumes rather than
clearing it while retaining its refresh deadline. No-store/no-cache and rate-limit
responses keep their original semantics. Now-playing uses the largest supplied
artwork URL from an allowlisted Last.fm image CDN, not an invented upscale URL or
a reuploaded copy. The owner confirmed written artwork-display approval. Missing
or failed artwork does not block the song text.

Browser visibility is distinct from input/view focus. Visible `inactive` pages
continue foreground work even after a view blur; `hidden`/`paused`/`detached`
pages do not. Native focus handling is unchanged. This addresses a possible
WebKit fetch suspension; the specific friend's device symptom remains unverified.
The production public full-profile and individual-field endpoints were checked:
both return the footer without authentication and permit cross-origin browser
requests. A fresh Chromium session also completed the cross-origin request.
The owner confirmed closing the publishing app during the empty-record check;
that observation is not evidence of an unexpected clear. After reopening, the
public footer-only record was present and unexpired. No further live profile
sampling is planned without asking the owner to reopen the app first.

WebKit animates GIF/WebP through an HTML image backed by an opaque local Blob,
using the same downloaded/decrypted bytes as the Flutter renderer. There are no
extra media network requests. The widget preserves aspect ratio/fit, leaves
pointer events to Flutter, keeps the source across identical-byte rebuilds and
revokes its Blob on disposal. Backgrounding/reduced motion/autoplay-off replaces
the animation with its decoded still frame. Native and Chromium keep the existing
timed codec path. A visible-but-unfocused web window is not treated as hidden.

The browser regression verifies native element loading, preservation of the full
multi-frame payload across rebuilds, and cleanup. Physical iOS GIF animation and
scroll/overlay compositing still need device confirmation; Chromium is not Safari.

## Release

Local validation: `flutter analyze --no-pub` clean; full Flutter suite passed
432 tests with 3 skips; the Chrome-only animation regression passed separately;
Dart formatting and `git diff --check` clean. Coverage includes independent-device
publication/clearing, a different-account viewer with sharing disabled, online
visibility, footer-only records, resume/cache/rate-limit behaviour, artwork URL
validation, mobile fixed-frame scrolling and browser lifecycle policy.

Target all four CI platforms as Latest, update deltie.net and chat.deltie.net.
No local installation requested. CI/deployment results are appended only after
they actually complete. Device confirmation is still required for the friend's
iOS activity visibility and GIF playback symptoms.
