/// Reject callbacks from a different destination or a superseded login. Neither
/// tokens nor codes from unsolicited links are ever used to create a session.
Map<String, String> validateAuthCallback(
  Uri actual,
  Uri expected,
  String state,
) {
  if (actual.scheme != expected.scheme ||
      actual.host != expected.host ||
      actual.port != expected.port ||
      actual.path != expected.path ||
      actual.userInfo.isNotEmpty ||
      actual.hasFragment ||
      expected.queryParameters.entries.any(
        (entry) => actual.queryParameters[entry.key] != entry.value,
      )) {
    throw const FormatException('The sign-in callback did not match this app.');
  }
  final params = actual.queryParametersAll;
  if (params['state']?.length != 1 ||
      params['state']!.single != state ||
      params.values.any((values) => values.length != 1)) {
    throw const FormatException(
      'This sign-in attempt expired or did not match. Please try again.',
    );
  }
  if (params.containsKey('error')) {
    throw const FormatException(
      'The identity provider did not complete sign-in.',
    );
  }
  return actual.queryParameters;
}
