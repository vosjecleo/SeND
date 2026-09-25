# Networking and privacy

SeND intentionally limits the network destinations it contacts.

Current baseline: 0.9.34+106. Security claims describe implemented boundaries,
not an independent security certification; see [1.0 readiness](RELEASE_READINESS.md).

## Configured Matrix homeserver

Automatic after login. Sync, authentication, room state, profile data, search,
media, encryption backup, and homeserver URL-preview requests go to the user's
configured homeserver. Federation is performed by homeservers and is not a
separate client connection.

Message link previews use the Matrix homeserver preview endpoint by default. If
the homeserver cannot produce a preview, SeND normally shows the plain
link and does not contact that site from the user's IP address.

Privacy settings contain an optional `Fetch link previews directly on this
device` fallback. It is off on every new installation. When explicitly enabled,
the client may fetch a public HTTP(S) page only after the homeserver preview
fails. Every DNS result and redirect target must be public and the actual TLS
peer address is validated before sending a request, so DNS rebinding cannot
redirect preview traffic into a private network. Proxies and cookies are
disabled, documents and images are bounded, and strict content-type, redirect,
and timeout limits apply. Embedded video candidates are exposed only in this
opt-in mode after a bounded range probe validates their public host, redirects,
content type, and declared size. Pressing Play then streams from that validated
public media URL.
Matrix tokens and headers are never sent to a preview site.

## MatrixRTC and WebRTC infrastructure

User-triggered when joining a voice room/call or enabling camera/screen share.
MatrixRTC state is exchanged through Matrix. Media may connect to ICE, STUN,
TURN, and MatrixRTC infrastructure advertised by the homeserver/RTC setup.
Linux screen sharing uses standard desktop portals and PipeWire where required.

## KLIPY proxy and legacy GIF media

Opening the GIF picker can request trending results from
`https://deltie.net/api/servers/klipy/search` (same-origin API routing on web).
Typing a search sends the query to that HTTPS proxy. The proxy holds the shared
KLIPY API key; release binaries do not contain it. Previews and selected GIFs
contact validated provider media hosts. Older GIPHY favourites remain readable;
that legacy traffic is not evidence that new search uses GIPHY.

Search JSON is capped at 2 MiB and GIF downloads at 25 MiB. Both use connection
and inactivity timeouts, status/content-type validation, and bounded redirects.
The reference proxy accepts forwarded client addresses only from configured
trusted reverse-proxy networks, bounds rate-limit identity state, and limits
concurrent upstream requests per process.

## External links and files

User-triggered only. Choosing Open externally passes an explicitly selected URL
or a private temporary attachment file to the operating system. SeND does
not fetch the destination first. Temporary decrypted files use randomized names
and private Unix permissions, then age out through cleanup.

## Local encrypted-media proxy

Automatic only while encrypted media is being played. SeND binds an HTTP
range server to `127.0.0.1` on a random port. Random capability paths refer to
credentials and AES material held only in memory. URLs and logs never contain
Matrix access tokens, keys, or IVs. Entries expire, are LRU bounded, and are
removed when playback ends, on logout, and at shutdown.

Encrypted video must first pass a full-ciphertext declared SHA-256 check before
being exposed to the decoder. Seeking reuses the verified encrypted cache;
the loopback range interface does not imply unauthenticated early streaming.
Web uses bounded decrypted Blob playback rather than the native loopback proxy.

## Browser authentication and PWA push

On explicit browser sign-in, login-method discovery contacts the chosen
homeserver. SSO/OIDC opens its advertised identity-provider flow; OIDC uses SDK
PKCE and session persistence. Native callback listeners bind only loopback at a
random port/path. Web callbacks validate origin, path, session and state before
handing the result back through a same-origin BroadcastChannel. Callback query
strings must not be logged or cached by hosting infrastructure. Tokens are not
stored in callback localStorage. See [the required nginx rule](web-deployment.md).

Account authentication does not verify encryption devices or restore lost keys.
Browser/PWA storage partition behaviour and real-provider round trips need
device testing. Closing or interrupting an unfinished sign-in may require retry.

The hosted PWA's Web Push gateway accepts short-lived Matrix OpenID proof and
opaque subscription capabilities, not Matrix access tokens or decrypted message
bodies. Browser alerts contain generic room activity; OS/browser push services
are part of delivery. This is separate from Android's ntfy distributor path.

## X/Twitter preview compatibility

X/Twitter links use FxTwitter as their preview source by default because
the original service frequently does not return usable OpenGraph metadata. The
visible incoming link remains unchanged. Newly sent links are rewritten
to FxTwitter while the setting is enabled. This behavior is configurable and
does not bypass the homeserver-first preview policy; direct webpage traffic
still requires the separate privacy opt-in.

## Android UnifiedPush

Configured from Android notification settings. SeND uses the standard
UnifiedPush distributor protocol and contains no shared ntfy credentials. The
selected distributor supplies a
private, high-entropy endpoint. SeND registers that complete endpoint as
the Matrix pushkey through the Matrix gateway on the same ntfy origin and keeps
it in private Android preferences. For example, a `push.deltie.net` capability
uses `https://push.deltie.net/_matrix/push/v1/notify`, while an `ntfy.sh`
capability uses the corresponding `ntfy.sh` gateway. The endpoint is a bearer
capability and is never displayed in the UI or written to logs.

Distributor registration is requested only during setup, an explicit refresh,
or a registration failure. The asynchronous endpoint callback is authoritative.
On foreground resume, reconnect, endpoint rotation, and every 12 hours while a
network is available, SeND instead verifies that the homeserver retained
the exact `event_id_only` Matrix pusher and repairs stale or missing same-device
entries without asking the distributor to rotate its capability. Notification
settings expose stage timestamps and a gateway-to-receiver test; the private
endpoint itself never enters logs, visible diagnostics, or WorkManager input.

Release builds use an installed external distributor such as ntfy. Embedded
Firebase-compatible WebPush is disabled until SeND has a dedicated,
VAPID-configured Matrix WebPush gateway; it cannot safely reuse the ntfy
gateway contract.

The gateway and distributor receive Matrix room/event metadata sufficient to
wake the application. The push path is not trusted as a source of plaintext.
After delivery, a short-lived foreground hand-off keeps the process awake until
a bounded Android worker contacts the configured homeserver, restores the
existing local crypto store, synchronizes the event and decrypts its body
on-device. Only bounded renderable notification fields cross the local
Flutter/Android method channel; access tokens, room keys, and crypto material do
not. Failed resolution is reported in private diagnostics without leaving a
content-free message alert behind.

## Release update checks

The signed-in application performs one bounded advisory check per process
against `https://deltie.net/SeND/releases.json`; Settings also exposes an
explicit retry. The checker does not download or install an update itself.
