import 'dart:convert';
import 'platform_io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'private_file_store.dart';
import 'browser_private_store.dart';
import 'emoji_repository.dart';
import 'personal_data.dart';
import 'package:html/parser.dart' as html_parser;

/// Small bounded local index for favourite Unicode emoji and Matrix stickers.
/// Sticker media remains in the normal Matrix/media cache; this file stores
/// identifiers only and is removed with ordinary application data.
final class FavouriteReactionsStore extends ChangeNotifier {
  FavouriteReactionsStore._();

  static final instance = FavouriteReactionsStore._();
  static const _maximumPerKind = 100;
  PersonalData? _account;
  bool _accountScoped = false;
  void bind(PersonalData? account) {
    _accountScoped = true;
    _account?.removeListener(notifyListeners);
    _account = account;
    account?.addListener(notifyListeners);
    notifyListeners();
  }

  Future<void> importDeviceFavourites() async {
    await load();
    final account = _account;
    if (account == null) return;
    for (final value in _emoji) {
      await account.set('fav.emoji:$value', true);
    }
    for (final value in _stickers) {
      await account.set('fav.sticker:$value', true);
    }
  }

  File? _file;
  bool _loaded = false;
  bool _readFailed = false;
  String? get warning => _readFailed
      ? 'Could not open saved favourites. Existing data was kept.'
      : null;
  final List<String> _emoji = [];
  final List<String> _stickers = [];
  final Map<String, int> _emojiUsage = {};
  final Map<String, int> _stickerUsage = {};
  Map<String, int> get stickerUsage =>
      _account?.usage('sticker') ??
      (_accountScoped ? const {} : Map.unmodifiable(_stickerUsage));
  Map<String, int> get emojiUsage =>
      _account?.usage('emoji') ??
      (_accountScoped ? const {} : Map.unmodifiable(_emojiUsage));

  Future<void> recordEmoji(String key) async {
    if (_accountScoped && _account == null) return;
    if (_account case final account?) return account.recordUsage('emoji', key);
    await load();
    _emojiUsage[key] = (_emojiUsage[key] ?? 0) + 1;
    if (_emojiUsage.length > 200) {
      final least = _emojiUsage.keys.reduce(
        (a, b) => _emojiUsage[a]! <= _emojiUsage[b]! ? a : b,
      );
      _emojiUsage.remove(least);
    }
    notifyListeners();
    await _save();
  }

  Future<void> recordSentMessage(String text, String? html) async {
    if (_accountScoped && _account == null) return;
    final catalogue = await EmojiRepository.instance.load();
    final known = catalogue.map((entry) => entry.emoji).toSet();
    final counts = <String, int>{};
    // Grapheme clusters prevent matching part of a skin-tone/ZWJ emoji.
    for (final character in text.characters) {
      if (known.contains(character)) {
        counts.update(character, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    if (html != null) {
      for (final element
          in html_parser
              .parseFragment(html)
              .querySelectorAll('img[data-mx-emoticon]')) {
        final source = element.attributes['src'];
        if (source != null && Uri.tryParse(source)?.scheme == 'mxc') {
          counts.update(source, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    if (_account case final account?) {
      for (final entry in counts.entries) {
        for (var i = 0; i < entry.value; i++) {
          await account.recordUsage('emoji', entry.key);
        }
      }
      return;
    }
    await load();
    for (final entry in counts.entries) {
      _emojiUsage.update(
        entry.key,
        (n) => n + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    _boundUsage(_emojiUsage);
    notifyListeners();
    await _save();
  }

  Future<void> recordSticker(Uri uri) async {
    if (_accountScoped && _account == null) return;
    if (_account case final account?) {
      return account.recordUsage('sticker', uri.toString());
    }
    await load();
    final key = uri.toString();
    _stickerUsage.update(key, (n) => n + 1, ifAbsent: () => 1);
    _boundUsage(_stickerUsage);
    notifyListeners();
    await _save();
  }

  void _boundUsage(Map<String, int> usage) {
    while (usage.length > 200) {
      usage.remove(usage.keys.reduce((a, b) => usage[a]! <= usage[b]! ? a : b));
    }
  }

  List<String> get emoji =>
      _account?.favourites('emoji') ??
      (_accountScoped ? const [] : List.unmodifiable(_emoji));
  List<String> get stickers =>
      _account?.favourites('sticker') ??
      (_accountScoped ? const [] : List.unmodifiable(_stickers));

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!kIsWeb) {
        final support = await getApplicationSupportDirectory();
        _file = File(
          path.join(support.path, 'deltiecord', 'reaction_favourites.json'),
        );
        if (!await privateFileExists(_file!)) return;
      }
      final text = kIsWeb
          ? await BrowserPrivateStore.read('reactions')
          : await readPrivateTextFile(_file!);
      if (text == null) return;
      final value = jsonDecode(text);
      if (value is! Map) return;
      final usage = value['usage'];
      final stickerUsage = value['sticker_usage'];
      if (stickerUsage is Map) {
        for (final entry in stickerUsage.entries.take(200)) {
          if (entry.key is String && entry.value is int && entry.value > 0) {
            _stickerUsage[entry.key as String] = entry.value as int;
          }
        }
      }
      if (usage is Map) {
        for (final entry in usage.entries.take(200)) {
          if (entry.key is String && entry.value is int && entry.value > 0) {
            _emojiUsage[entry.key as String] = entry.value as int;
          }
        }
      }
      _emoji.addAll(
        (value['emoji'] as List? ?? const []).whereType<String>().take(
          _maximumPerKind,
        ),
      );
      _stickers.addAll(
        (value['stickers'] as List? ?? const []).whereType<String>().take(
          _maximumPerKind,
        ),
      );
    } catch (_) {
      _readFailed = true;
      _emoji.clear();
      _stickers.clear();
    }
  }

  bool isEmojiFavourite(String value) => emoji.contains(value);
  bool isStickerFavourite(Uri value) => stickers.contains(value.toString());

  Future<void> toggleEmoji(String value) async {
    if (_accountScoped && _account == null) return;
    if (_account case final account?) {
      return account.set('fav.emoji:$value', !isEmojiFavourite(value));
    }
    await load();
    _toggle(_emoji, value);
    await _save();
  }

  Future<void> toggleSticker(Uri value) async {
    if (_accountScoped && _account == null) return;
    if (_account case final account?) {
      return account.set('fav.sticker:$value', !isStickerFavourite(value));
    }
    await load();
    _toggle(_stickers, value.toString());
    await _save();
  }

  void _toggle(List<String> values, String value) {
    if (values.remove(value)) {
      notifyListeners();
      return;
    }
    values.insert(0, value);
    if (values.length > _maximumPerKind) values.removeLast();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_readFailed) throw StateError(warning!);
    if (kIsWeb) {
      await BrowserPrivateStore.write(
        'reactions',
        jsonEncode({
          'emoji': _emoji,
          'stickers': _stickers,
          'usage': _emojiUsage,
          'sticker_usage': _stickerUsage,
        }),
      );
      return;
    }
    final file = _file;
    if (file == null) return;
    await writePrivateTextFile(
      file,
      jsonEncode({
        'emoji': _emoji,
        'stickers': _stickers,
        'usage': _emojiUsage,
        'sticker_usage': _stickerUsage,
      }),
    );
  }
}
