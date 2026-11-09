const passwordRecoveryRedirectUrl =
    'https://app.educador.rgw.app/recover/complete';

bool isRecoveryTokenHash(String value) =>
    RegExp(r'^(?:pkce_)?(?:[a-fA-F0-9]{56}|[a-fA-F0-9]{64})$').hasMatch(value);

String? recoveryTokenFromUri(Uri uri) {
  if (uri.path != '/recover/complete' ||
      uri.queryParameters.containsKey('token_hash')) {
    return null;
  }
  try {
    final parameters = Uri(query: uri.fragment).queryParametersAll;
    final values = parameters['token_hash'];
    if (values == null ||
        values.length != 1 ||
        !isRecoveryTokenHash(values.single)) {
      return null;
    }
    return values.single;
  } on FormatException {
    return null;
  }
}
