part of 'matrix_backend.dart';

const _browserLoginTypes = {'m.login.password', 'm.login.sso', 'm.login.token'};

void _requireSecureHomeserver(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const FormatException(
      'Browser sign-in requires an HTTPS homeserver.',
    );
  }
}

extension _MatrixBrowserAuthentication on MatrixBackend {
  Future<LoginMethods> _discoverLoginMethods(Uri homeserver) async {
    _requireSecureHomeserver(homeserver);
    // Discovery must not race with, or change the server of, the active client.
    final probe = Client(
      'SeND login discovery',
      database: _matrix.database,
      supportedLoginTypes: _browserLoginTypes,
    );
    try {
      final result = await probe.checkHomeserver(
        homeserver,
        fetchAuthMetadata: true,
      );
      _requireSecureHomeserver(probe.homeserver!);
      return LoginMethods(
        homeserver: probe.homeserver!,
        password: result.$3.any((flow) => flow.type == 'm.login.password'),
        sso: result.$3.any((flow) => flow.type == 'm.login.sso'),
        oidc: result.$4 != null,
      );
    } finally {
      await probe.dispose(closeDatabase: false);
    }
  }

  Future<void> _loginWithBrowser(Uri homeserver, {required bool oidc}) async {
    if (_browserAuthenticationActive || _matrix.isLogged()) return;
    _requireSecureHomeserver(homeserver);
    _browserAuthenticationActive = true;
    _browserAuthenticationCanceled = false;
    _status = SessionStatus.signingIn;
    _connectionStatus = ConnectionStatus.connecting;
    _error = null;
    AuthBrowser? browser;
    try {
      final random = Random.secure();
      final nonce = base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      // Prepare the web popup synchronously within the original user gesture.
      final preparing = AuthBrowser.prepare(nonce);
      _notifyBackendListeners();
      browser = await preparing;
      _activeAuthBrowser = browser;
      void checkCanceled() {
        if (_browserAuthenticationCanceled) throw StateError('Canceled');
      }

      checkCanceled();
      _matrix.supportedLoginTypes = _browserLoginTypes;
      final discovery = await _matrix.checkHomeserver(
        homeserver,
        fetchAuthMetadata: true,
      );
      checkCanceled();
      _requireSecureHomeserver(_matrix.homeserver!);
      if (oidc) {
        final metadata = discovery.$4;
        if (metadata == null) {
          throw StateError('This server does not offer OIDC sign-in.');
        }
        _requireSecureHomeserver(metadata.authorizationEndpoint);
        _requireSecureHomeserver(metadata.tokenEndpoint);
        _requireSecureHomeserver(metadata.registrationEndpoint);
        final clientData = await _matrix.registerOidcClient(
          redirectUris: [browser.redirect],
          applicationType: kIsWeb
              ? OidcApplicationType.web
              : OidcApplicationType.native,
          clientInformation: OidcClientInformation(
            clientName: 'SeND',
            clientUri: kIsWeb
                ? Uri.parse(browser.redirect.origin)
                : Uri.parse('https://deltie.net'),
            logoUri: null,
            tosUri: null,
            policyUri: null,
          ),
        );
        final session = await _matrix.initOidcLoginSession(
          oidcClientData: clientData,
          redirectUri: browser.redirect,
          responseMode: OidcResponseMode.query,
        );
        checkCanceled();
        final callback = await browser.authenticate(session.authenticationUri);
        checkCanceled();
        final parameters = validateAuthCallback(
          callback,
          browser.redirect,
          session.state,
        );
        final code = parameters['code'];
        if (code == null || code.isEmpty) {
          throw const FormatException('No authorization code was returned.');
        }
        // SDK owns PKCE exchange, persistent tokens and refresh. Browser login
        // deliberately does not mark the new encryption device as verified.
        await _matrix.oidcLogin(
          session: session,
          code: code,
          state: session.state,
        );
      } else {
        if (!discovery.$3.any((flow) => flow.type == 'm.login.sso')) {
          throw StateError('This server does not offer browser sign-in.');
        }
        final redirect = browser.redirect.replace(
          queryParameters: {
            ...browser.redirect.queryParameters,
            'state': nonce,
          },
        );
        final authorization = _matrix.homeserver!
            .resolve('_matrix/client/v3/login/sso/redirect')
            .replace(queryParameters: {'redirectUrl': redirect.toString()});
        final callback = await browser.authenticate(authorization);
        checkCanceled();
        final parameters = validateAuthCallback(callback, redirect, nonce);
        final token = parameters['loginToken'];
        if (token == null || token.isEmpty) {
          throw const FormatException('No login token was returned.');
        }
        await _matrix.login(
          'm.login.token',
          token: token,
          refreshToken: true,
          initialDeviceDisplayName: kIsWeb
              ? 'SeND Web'
              : 'SeND ${Platform.operatingSystem}',
        );
      }
      if (_browserAuthenticationCanceled) {
        if (_matrix.isLogged()) await _matrix.logout();
        throw StateError('Canceled');
      }
      await _finishPasswordAuthentication();
    } catch (error) {
      _status = SessionStatus.signedOut;
      _connectionStatus = ConnectionStatus.offline;
      // Never expose callback URLs, authorization codes or tokens in errors.
      _error = error is FormatException
          ? error.message
          : 'Browser sign-in was canceled or could not complete. Please try again.';
    } finally {
      await browser?.close();
      _activeAuthBrowser = null;
      _browserAuthenticationActive = false;
      _notifyBackendListeners();
    }
  }
}
