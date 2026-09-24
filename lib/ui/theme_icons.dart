part of 'json_theme.dart';

const _tangoIcons = <String, String>{
  'home': 'actions-go-home',
  'search': 'actions-system-search',
  'inbox': 'apps-internet-mail',
  'add': 'actions-list-add',
  'settings': 'categories-preferences-system',
  'microphone': 'devices-audio-input-microphone',
  'emoji': 'emotes-face-smile',
  'gifs': 'mimetypes-video-x-generic',
  'stickers': 'mimetypes-image-x-generic',
  'camera': 'devices-camera-photo',
  'files': 'places-folder',
  'send': 'actions-mail-forward',
  'mute': 'status-audio-volume-muted',
  'audio': 'status-audio-volume-high',
  'servers': 'places-network-server',
  'pause': 'actions-media-playback-pause',
  'stop': 'actions-media-playback-stop',
};

/// Embedded PNG only: no paths, URL requests, SVG scripts, fonts or archives.
Map<String, Uint8List> parseThemeIcons(Object? raw) {
  final icons = <String, Uint8List>{};
  if (raw is! Map) return icons;
  for (final role in _tangoIcons.keys) {
    final value = raw[role];
    if (value is! String ||
        !value.startsWith('data:image/png;base64,') ||
        value.length > 11000) {
      continue;
    }
    try {
      final bytes = base64Decode(value.substring(22));
      if (bytes.length < 33 ||
          bytes.length > 8192 ||
          base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=') {
        continue;
      }
      final header = ByteData.sublistView(bytes);
      if (header.getUint32(8) != 13 ||
          ascii.decode(bytes.sublist(12, 16)) != 'IHDR') {
        continue;
      }
      final w = header.getUint32(16), h = header.getUint32(20);
      if (w == 0 || h == 0 || w > 128 || h > 128) continue;
      var valid = true;
      for (var offset = 8; offset < bytes.length;) {
        if (offset + 12 > bytes.length) {
          valid = false;
          break;
        }
        final length = header.getUint32(offset);
        if (length > bytes.length - offset - 12 ||
            header.getUint32(offset + 4) == 0x6163544c) {
          valid = false;
          break;
        }
        offset += length + 12;
      }
      if (valid) icons[role] = bytes;
    } on FormatException {
      /* Invalid entries use the stock fallback. */
    }
  }
  return Map.unmodifiable(icons);
}

class ThemeIcon extends StatelessWidget {
  const ThemeIcon(
    this.icon, {
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    super.key,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
    final role = _role(icon);
    final chrome = Theme.of(context).extension<ThemeChrome>();
    if (role == null || chrome == null) return fallback;
    final bytes = chrome.customIcons[role];
    if (bytes == null && chrome.iconPack != 'Tango') return fallback;
    final dimension = size ?? IconTheme.of(context).size ?? 24;
    final image = bytes != null
        ? Image.memory(
            bytes,
            width: dimension,
            height: dimension,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, error, stack) => fallback,
          )
        : Image.asset(
            'assets/icons/tango/${_tangoIcons[role]}.png',
            width: dimension,
            height: dimension,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => fallback,
          );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: (IconTheme.of(context).opacity ?? 1) * (color?.a ?? 1),
          child: image,
        ),
      ),
    );
  }

  static String? _role(IconData? icon) => switch (icon) {
    Icons.home || Icons.home_filled || Icons.home_outlined => 'home',
    Icons.search || Icons.search_outlined => 'search',
    Icons.inbox || Icons.inbox_outlined => 'inbox',
    Icons.add || Icons.add_circle_outline => 'add',
    Icons.settings || Icons.settings_outlined => 'settings',
    Icons.mic || Icons.mic_none || Icons.mic_outlined => 'microphone',
    Icons.mic_off || Icons.headset_off || Icons.volume_off => 'mute',
    Icons.headphones || Icons.volume_up => 'audio',
    Icons.emoji_emotions ||
    Icons.emoji_emotions_outlined ||
    Icons.emoji_emotions_rounded => 'emoji',
    Icons.gif_box || Icons.gif_box_outlined => 'gifs',
    Icons.sticky_note_2 ||
    Icons.sticky_note_2_outlined ||
    Icons.image_outlined => 'stickers',
    Icons.camera_alt || Icons.camera_alt_outlined => 'camera',
    Icons.folder || Icons.folder_outlined || Icons.attach_file => 'files',
    Icons.send || Icons.send_outlined => 'send',
    Icons.travel_explore_outlined ||
    Icons.dns ||
    Icons.dns_outlined => 'servers',
    Icons.pause || Icons.pause_rounded => 'pause',
    Icons.stop || Icons.stop_rounded => 'stop',
    _ => null,
  };
}
