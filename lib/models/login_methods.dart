class LoginMethods {
  const LoginMethods({
    required this.homeserver,
    this.password = false,
    this.sso = false,
    this.oidc = false,
  });
  final Uri homeserver;
  final bool password;
  final bool sso;
  final bool oidc;
}
