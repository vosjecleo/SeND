import 'package:characters/characters.dart';

/// Count user-perceived characters, never split a combining mark or emoji.
String? normalizedProfilePronouns(String? value) =>
    value?.trim().characters.take(16).toString();
