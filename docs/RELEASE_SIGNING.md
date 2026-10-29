# Release signatures

SeND verifies Ed25519 signatures before trusting update metadata. HTTPS, download
size limits, SHA-256, AppImage rollback copies and package-manager checks still
apply. A failed signature check never falls back to unsigned metadata.

The app embeds public keys in `lib/services/release_signatures.dart`.
`packaging/release-trust.json` must contain the same keys. A packaging test checks
that they match. Private keys do not belong in the repository, build outputs,
logs or release assets.

## Setup

Keep the PEM signing key in a private directory with mode 0700, with the key file
at mode 0600. Back it up separately in secure storage. Set repository secret
`SEND_RELEASE_SIGNING_KEY` to the complete PEM contents, including header,
footer and newlines.

For mirror publication, set `SEND_RELEASE_SIGNING_KEY_FILE` to the private file.
The local publisher defaults to Cleo's release-signing directory. CI writes its
secret to a temporary mode-0600 file and removes it after signing.

The first publication after adopting signatures requires
`SEND_RELEASE_BOOTSTRAP=1` when running `packaging/publish-release.sh`. This
explicitly accepts the existing unsigned channel metadata as the initial
migration source. Check its versions and artifact hashes first. Do not use this
option for later releases or to bypass a failed signature check.

## Publication and checks

The GitHub release workflow signs `SHA256SUMS`; Flatpak publication signs
`FLATPAK-SHA256SUMS`. The mirror publisher verifies those signatures before
using the hashes. It signs the final `releases.json` after merging the selected
channel, and publishes `releases.json.sig` alongside it. Flatpak additions must
also re-sign this manifest.

PWAs fetch the same signed bytes as `/release-metadata.json` and its `.sig`
file on the app's own origin. Publication updates both copies. PWA-only patches
retain them when switching the app directory, so update checks do not need
cross-origin access to the downloads site.

Self-hosted PWAs must also serve or proxy this signed pair at those same-origin
paths. They can copy the public files from the release mirror; they do not need
the publisher's private key.

Signatures cover the exact file bytes, prefixed with
`SeND release metadata v1` and a newline. Signature envelopes identify the
algorithm and trusted key, not a public key supplied by the server.

Manifests expire after 90 days. Publish a release or renew the unchanged
manifest's signature before then. Renewal changes only `signed_at`,
`expires_at` and the signature, not channel versions or artifact hashes:

```sh
python3 packaging/sign-release.py releases.json releases.json.sig --manifest
python3 packaging/sign-release.py releases.json releases.json.sig --verify --manifest
```

Renewal must first verify the downloaded manifest and its existing signature.
If it has already expired, verify the signature without `--manifest`, then
check the channel versions and hashes against their published release tags
before renewing. Do not use the bootstrap switch to bypass expiry.
Stage and replace both files together, retaining the previous pair for diagnosis.
A reader encountering a temporary mismatched pair rejects it and can retry.
Do not put a private signing key on the public web server just for renewal.

The client rejects expired metadata, signatures from unknown keys and metadata
older than the most recent signed manifest it has accepted. It separately
compares the proposed version/build with the installed version, so signed older
packages do not become automatic downgrade offers. A deliberate rollback needs
freshly signed channel metadata; downgrading an installed app remains manual.

## Rotation and recovery

For planned rotation, generate a new key and ship both public keys in an app
update while still signing with the old key. Keep the old signer during that
upgrade period. Then switch the CI secret and local key, and later remove the
retired public key. Older clients which never received the new key need a manual
upgrade once publication switches signers.

If the private key is lost, recover its secure backup. If it is compromised,
stop publication, revoke it in the next trusted distribution and tell users to
upgrade through an independently verified installer or package source. Do not
offer an unsigned fallback or trust a replacement key downloaded from the same
compromised metadata endpoint. Signatures cannot undo a compromised installed
binary, signing runner or trusted key.
