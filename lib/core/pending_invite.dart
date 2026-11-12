import 'package:flutter/foundation.dart';

import 'invite_link.dart';
import 'pending_invite_storage.dart';

const _acceptKey = 'educador.pendingInvite';
const _startKey = 'educador.pendingStartInvite';
final _validToken = RegExp(r'^[0-9a-f]{64}$');

String? get pendingInvite {
  final token = readStoredInvite(_acceptKey);
  return token != null && _validToken.hasMatch(token) ? token : null;
}

void setPendingInvite(String? token) {
  writeStoredInvite(
    _acceptKey,
    token != null && _validToken.hasMatch(token) ? token : null,
  );
}

InviteAuthLink? get pendingStartInvite {
  final stored = readStoredInvite(_startKey);
  if (stored == null) return null;
  return InviteAuthLink.fromUri(Uri(path: '/invite/start', fragment: stored));
}

void setPendingStartInvite(InviteAuthLink? link) {
  writeStoredInvite(
    _startKey,
    link == null
        ? null
        : Uri(
            queryParameters: {
              'token_hash': link.tokenHash,
              'type': link.type,
              'token': link.token,
            },
          ).query,
  );
  pendingStartInviteNotifier.value = link;
}

/// Lets the mounted start screen react when a new link replaces the current
/// one. GoRouter does not rebuild a route whose path is unchanged.
final pendingStartInviteNotifier = ValueNotifier<InviteAuthLink?>(
  pendingStartInvite,
);

String? inviteTokenFromUri(Uri uri) {
  if (uri.path != '/invite/accept') return null;
  try {
    if (uri.hasQuery && uri.hasFragment) return null;
    final params = uri.hasFragment
        ? Uri(query: uri.fragment).queryParametersAll
        : uri.queryParametersAll;
    if (params.length != 1 || params['token']?.length != 1) return null;
    final token = params['token']!.single;
    return _validToken.hasMatch(token) ? token : null;
  } on FormatException {
    return null;
  }
}
