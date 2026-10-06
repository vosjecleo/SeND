# Animated banner colour investigation

2026-10-06, build 119. Investigation only; no rendering changes applied.

## Reproduction

The supplied `I LOVE THEM.gif` is a 250 × 250 GIF with 121 frames. Inline
playback has pink areas that become black after using it as a profile banner.

A local Flutter test compared the original GIF with the output of
`cropProfileImage`, using a centred 250 × 83 crop and no resizing. Flutter's
codec decoded both outputs as 121 frames. Across those frames, 777,470 pixels
that were pink in the original crop became near-black in the converted banner.
This reproduces the colour problem without the profile widget or upload step.

The private sample and temporary diagnostic test are not included in the repo.

## Paths involved

- Inline playback decodes the original bytes with Flutter's image codec.
- Profile editing routes the banner through `profile_image_cropper.dart`.
  `cropProfileImage` uses the Dart `image` package to decode, orient, crop and
  encode it as PNG. Animated output is APNG.
- `matrix_profiles.dart` uploads that result as `profile-banner.png`.
- `profile_card.dart` renders the converted bytes with `Image.memory`.

The `image` 4.9.2 decoder's GIF frames already differ from Flutter's decoding
of the original. Frames use palettes of both 256 and 128 colours. The APNG
encoder also quantizes animated palette images. Converting the cropped frames
to RGBA before APNG encoding changed some pixels, but left the same pink-to-black
count. Avoiding that final quantization alone is not a sufficient fix.

## Next checks

1. Compare frame palettes, transparency and disposal/composition against a
   second decoder to identify where the first incorrect pixels appear.
2. Test cropping fully composited RGBA frames from a verified decoder, preserving
   frame delays and looping. Add a small generated regression fixture rather
   than committing the user's GIF.
3. Check banner and avatar playback on native and web targets before adopting
   a new conversion path, including memory use and output size.

Confidence is high that this sample is corrupted during banner conversion,
not just displayed incorrectly by the profile widget. The exact decoding or
composition defect is not yet isolated. This does not establish a cause for
unrelated GIF playback reports.

## Follow-up: frame composition isolated

A second probe decoded each GIF frame separately with `GifDecoder.decodeFrame`
and compared its opaque pixels with Flutter's composited frame at the same
coordinates. All 121 frames matched: zero differing opaque pixels. The same
library's complete animated decode differed at 5,251,886 pixels. The first frame
matched; the corruption began on frame 1, before cropping or PNG encoding.

The sample's first eight frames all use disposal method 1 and full-canvas
rectangles. Their palettes change from 256 to 128 entries. This narrows the
failure to the library's animated frame assembly, not the individual frame
decoder, banner widget, or network transfer. The precise faulty operation in
that assembly still needs isolation; palette remapping is a suspect, not a
confirmed explanation.

The next fix to test is cropping fully composited RGBA frames from Flutter's
codec, then encoding them with their original timing and loop policy. That
avoids the faulty assembly path. It needs a bounded-memory implementation and
native/web checks before replacing the crop pipeline. No banner-conversion
change has been applied in this patch.

Separately, cropped animated avatars are APNG. Avatar animation detection now
recognizes that format so selection, hover and reduced-motion rules apply to
them too. This does not repair already corrupted banner uploads.
