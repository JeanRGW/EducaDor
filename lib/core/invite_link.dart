class InviteAuthLink {
  const InviteAuthLink({
    required this.tokenHash,
    required this.type,
    required this.token,
  });

  final String tokenHash;
  final String type;
  final String token;

  (String, String, String) get identity => (tokenHash, type, token);

  static InviteAuthLink? fromUri(Uri uri) {
    if (uri.path != '/invite/start' || uri.hasQuery) return null;
    try {
      final parameters = Uri(query: uri.fragment).queryParametersAll;
      if (parameters.length != 3 ||
          parameters.values.any((values) => values.length != 1)) {
        return null;
      }
      final hash = parameters['token_hash']?.single ?? '';
      final type = parameters['type']?.single ?? '';
      final token = parameters['token']?.single ?? '';
      if (!RegExp(r'^(?:[a-fA-F0-9]{56}|[a-fA-F0-9]{64})$').hasMatch(hash) ||
          !['invite', 'magiclink'].contains(type) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        return null;
      }
      return InviteAuthLink(tokenHash: hash, type: type, token: token);
    } on FormatException {
      return null;
    }
  }
}
