import 'package:educador/core/invite_link.dart';
import 'package:educador/core/pending_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final token = 'a' * 64;
  tearDown(() {
    setPendingInvite(null);
    setPendingStartInvite(null);
  });

  test('accepts one valid fragment or legacy query token', () {
    expect(inviteTokenFromUri(Uri.parse('/invite/accept#token=$token')), token);
    expect(inviteTokenFromUri(Uri.parse('/invite/accept?token=$token')), token);
    expect(
      inviteTokenFromUri(Uri.parse('/invite/accept#token=$token&token=$token')),
      isNull,
    );
    expect(
      inviteTokenFromUri(Uri.parse('/invite/accept?token=$token#token=$token')),
      isNull,
    );
    expect(inviteTokenFromUri(Uri.parse('/invite/accept#token=bad')), isNull);
  });

  test('start link round-trips through tab storage', () {
    final link = InviteAuthLink.fromUri(
      Uri.parse('/invite/start#token_hash=${'b' * 64}&type=invite&token=$token'),
    )!;
    setPendingStartInvite(link);
    expect(pendingStartInvite?.identity, link.identity);
    setPendingStartInvite(null);
    expect(pendingStartInvite, isNull);
  });

  test('pending token is validated and cleared', () {
    setPendingInvite(token);
    expect(pendingInvite, token);
    setPendingInvite('bad');
    expect(pendingInvite, isNull);
  });
}
