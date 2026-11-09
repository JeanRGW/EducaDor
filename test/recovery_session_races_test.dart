import 'dart:async';
import 'dart:collection';

import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/repositories.dart';
import 'package:educador/data/session/session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = User(
  id: 'user',
  fullName: 'Ana',
  email: 'a@example.test',
  initials: 'A',
);
const _normal = AppSession(user: _user, contexts: []);
const _recovery = AppSession(
  user: _user,
  contexts: [],
  recoveringPassword: true,
);

class _Auth extends AuthRepository {
  final responses = Queue<Future<AppSession?>>();
  @override
  Future<AppSession?> current() => responses.removeFirst();
  @override
  Future<void> signOut() async {}
}

void main() {
  for (final failOldRequest in [false, true]) {
    test(
      'a stale session refresh cannot overwrite recovery state: old error=$failOldRequest',
      () async {
        final auth = _Auth()..responses.add(Future.value(_normal));
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
        );
        addTearDown(container.dispose);
        await container.read(sessionProvider.future);
        final first = Completer<AppSession?>();
        final second = Completer<AppSession?>();
        auth.responses.addAll([first.future, second.future]);
        final controller = container.read(sessionProvider.notifier);
        final older = controller.reload();
        final newer = controller.reload();
        second.complete(_recovery);
        await newer;
        if (failOldRequest) {
          first.completeError(StateError('obsolete request'));
        } else {
          first.complete(_normal);
        }
        await older;
        expect(
          container.read(sessionProvider).value?.recoveringPassword,
          isTrue,
        );
      },
    );
  }

  test('logout invalidates a pending recovery refresh', () async {
    final auth = _Auth()..responses.add(Future.value(_recovery));
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    final pending = Completer<AppSession?>();
    auth.responses.add(pending.future);
    final controller = container.read(sessionProvider.notifier);
    final reload = controller.reload();
    await controller.logout();
    pending.complete(_recovery);
    await reload;
    expect(container.read(sessionProvider).value, isNull);
  });
}
