# SeND screenshot gallery

These screenshots show SeND build 115 in Chromium on 2026-10-03. The private
**SeND showcase** Space uses a test account and sample messages, not user chats.

Browse: [chat](#chat-threads-and-media), [packs](#sticker-picker-and-telegram-import),
[GIFs](#gif-search), [forums](#forums), [voice](#voice-channel-chat),
[profiles](#profile-editing), [activity](#activity-and-privacy),
[themes](#themes), [administration](#space-administration), [mobile](#mobile-layout).

## Chat, threads and media

The desktop layout keeps Space navigation, the conversation and an optional
discussion pane visible together. Rich text, spoilers and a sent sticker appear
in the same timeline.

![Desktop chat with a thread discussion](screenshots/desktop-chat-threads.png)

## Sticker picker and Telegram import

The expression picker groups emoji, GIFs and stickers. This example imports two
items from the public [Hot Cherry Telegram pack](https://t.me/addstickers/HotCherry).
The artwork belongs to its respective creator; no standalone pack assets are
redistributed here. Only the two imported samples are shown.

![Sticker picker with an imported sample pack](screenshots/sticker-picker.png)

Three static items from [Just zoo it!](https://t.me/addstickers/Animals) were
separately imported as custom emoji. The alias editor and resulting pack in the
picker are shown below; one emoji was also sent to the private showcase room.

![Custom emoji alias editor](screenshots/emoji-alias-editor.png)

![Imported custom emoji grouped by pack](screenshots/custom-emoji-picker.png)

## GIF search

KLIPY search results inside the expression picker. GIF and pack artwork belongs
to the respective creators and is shown only as part of the client UI.

![KLIPY cat GIF search](screenshots/gif-search.png)

## Forums

Forum channels organize discussions as named posts with tags and replies.

![Private showcase forum with two sample posts](screenshots/forums.png)

## Voice-channel chat

Preview a voice channel before joining, and keep its text conversation visible
beside it.

![Voice-channel preview with its chat panel](screenshots/voice-chat.png)

## Profile editing

The editor previews profile colours, biography and the status thought bubble.

![Profile editor with a live preview](screenshots/profile-editor.png)

## Activity and privacy

This is the **web** Activity settings page. Native desktop process detection is
not available in the PWA. Last.fm connection and sharing controls are shown.

![Web activity-sharing settings](screenshots/activity-settings.png)

## Themes

The bundled Aero example supplies its own appearance controls through the
declarative theme system. Both the controls and the resulting chat are shown.

![Aero theme settings](screenshots/theme-settings.png)

![Showcase chat using Aero](screenshots/aero-chat.png)

## Space administration

Roles, Matrix permission levels, Space access and shared timeline settings live
in Administration. The example uses the private showcase Space.

![Space administration settings](screenshots/space-administration.png)

## Mobile layout

The mobile layout, captured with Chromium's mobile emulation on Linux.

<img src="screenshots/mobile-chat.png" alt="Mobile showcase conversation" width="390">

<img src="screenshots/mobile-stickers.png" alt="Mobile sticker picker with the imported Hot Cherry sample" width="390">

## Capture notes

Captured with `grim` on the development laptop while build 116 was being prepared.
The full 34-item animated Hot Cherry import was slow; only the two sample
stickers and three static custom emoji were checked for these captures. Full-pack
and animated-emoji imports were not validated by this session.

No call was placed, microphone audio recorded or Last.fm account linked. Profile
editor changes were discarded, and no public community permissions were changed.

These are layout examples, not tests of animation, codecs, audio, notifications,
encryption verification or physical iOS behaviour.

### Taking new screenshots

Keep credentials, recovery keys, notification contents and unrelated windows
out of images. Use the private showcase rooms for future captures. Browser
mobile emulation cannot test iOS hardware. Do not ring
other people or publish test packs into shared production Spaces for a screenshot.
