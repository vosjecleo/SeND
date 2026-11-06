import 'dart:convert';
import 'package:crypto/crypto.dart';

const gifIdentityContentKey = 'net.deltie.send.gif_id';
String? validGifIdentity(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value) ? value : null;
String gifIdentityFor(String roomId, String eventId) =>
    sha256.convert(utf8.encode(jsonEncode([roomId, eventId]))).toString();
