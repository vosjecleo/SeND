import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'rtc_protocol.dart';

class RtcTransportCredentials {
  const RtcTransportCredentials(this.url, this.jwt);
  final Uri url;
  final String jwt;
  // Never include credentials in logs or exceptions.
  @override
  String toString() => 'RtcTransportCredentials(redacted)';
}

/// Only Matrix requests use the Matrix session token. Standalone SFU services
/// receive a short-lived OpenID proof, never that session token or media keys.
class RtcTransportApi {
  RtcTransportApi(this.client, {http.Client? httpClient})
    : _http = httpClient ?? client.httpClient;
  final Client client;
  final http.Client _http;

  Future<List<RtcTransport>> discover() async {
    for (final path in [
      '/client/v1/rtc/transports',
      '/client/unstable/org.matrix.msc4143/rtc/transports',
    ]) {
      try {
        final data = await client
            .request(RequestType.GET, path)
            .timeout(const Duration(seconds: 10));
        return RtcTransport.fromResponse(data);
      } on MatrixException catch (e) {
        if (!_unsupported(e)) rethrow;
      }
    }
    final known = await client
        .getWellknown(throwOnUpdateFailure: true)
        .timeout(const Duration(seconds: 10));
    return RtcTransport.fromResponse(known.additionalProperties);
  }

  Future<RtcTransportCredentials> authorize({
    required RtcTransport transport,
    required String roomId,
    required String memberId,
    String? publishingUserId,
  }) async {
    if (transport.url != null) {
      final body = <String, Object>{
        'url': transport.url.toString(),
        'room_id': roomId,
        'slot_id': rtcRoomSlot,
        'member_id': memberId,
        if (publishingUserId != null)
          'server_name': publishingUserId.substring(
            publishingUserId.indexOf(':') + 1,
          ),
      };
      try {
        final result = await client
            .request(
              RequestType.POST,
              '/client/unstable/io.element.msc4195/rtc/livekit/get_token',
              data: body,
            )
            .timeout(const Duration(seconds: 15));
        return _credentials(result, expectedUrl: transport.url);
      } on MatrixException catch (e) {
        // A transitional transport may expose the old service as well. Only
        // fall back on unsupported endpoints, never on denied authorization.
        if (!_unsupported(e) || transport.serviceUrl == null) rethrow;
      }
    }
    final service = transport.serviceUrl;
    final user = client.userID, device = client.deviceID;
    if (service == null || user == null || device == null) {
      throw StateError('No supported MatrixRTC authorization service');
    }
    final proof = await client
        .requestOpenIdToken(user, {})
        .timeout(const Duration(seconds: 10));
    final endpoint = service.replace(
      path: '${service.path.replaceFirst(RegExp(r'/+$'), '')}/sfu/get',
    );
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'room': roomId,
        'device_id': device,
        'openid_token': proof.toJson(),
      });
    final response = await _http
        .send(request)
        .timeout(const Duration(seconds: 15));
    // Do not expose raw service responses: they may contain proofs or JWTs.
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw StateError(
        'MatrixRTC authorization failed (${response.statusCode})',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      if (bytes.length + chunk.length > 64 * 1024) {
        throw StateError('MatrixRTC authorization response is too large');
      }
      bytes.addAll(chunk);
    }
    try {
      return _credentials(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      throw StateError('Invalid MatrixRTC authorization response');
    }
  }

  RtcTransportCredentials _credentials(Object? value, {Uri? expectedUrl}) {
    if (value is! Map) {
      throw StateError('Invalid MatrixRTC authorization response');
    }
    final jwt = value['jwt'];
    final url = expectedUrl ?? rtcSecureUrl(value['url'], websocket: true);
    if (url == null || jwt is! String || jwt.isEmpty || jwt.length > 16384) {
      throw StateError('Invalid MatrixRTC authorization response');
    }
    return RtcTransportCredentials(url, jwt);
  }

  bool _unsupported(MatrixException e) =>
      e.errcode == 'M_UNRECOGNIZED' ||
      e.response?.statusCode == 404 ||
      e.response?.statusCode == 405;
}
