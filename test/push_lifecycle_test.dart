import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:educador/data/models/models.dart';
import 'package:educador/data/repositories/push_lifecycle.dart';
import 'package:educador/data/repositories/notification_controller.dart'
    show notificationContextKey, validFirebaseConfig;

class FakeTransport implements PushTransport {
  bool available = true;
  PushPermission current = PushPermission.granted;
  String value = 'token-a';
  int prompts = 0;
  int deletes = 0;
  final controller = StreamController<String>.broadcast(sync: true);
  @override
  Future<bool> supported() async => available;
  @override
  Future<PushPermission> permission() async => current;
  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return current;
  }

  @override
  Future<String?> token() async => value;
  @override
  Future<void> deleteToken() async {
    deletes++;
  }

  @override
  Stream<String> get rotations => controller.stream;
}

class FakeStore implements PushStore, PushStoreFactory {
  String caller = 'a';
  String credential = 'jwt-a';
  final validCredentials = <String>{'jwt-a'};
  final owners = <String, String>{};
  @override
  PushStore? capture(String userId) {
    if (caller != userId) return null;
    return FakeOwnerStore(this, caller, credential);
  }

  bool preference = true;
  bool fail = false;
  final log = <String>[];
  Completer<void>? pending;
  @override
  Future<bool> enabled(String userId) async {
    log.add('read:$userId');
    return preference;
  }

  @override
  Future<void> setEnabled(bool value) async {
    if (fail) throw StateError('offline');
    preference = value;
    log.add('preference:$value');
  }

  @override
  Future<void> register(String token, String platform) async {
    log.add('register:$token');
    await pending?.future;
    if (fail) throw StateError('offline');
  }

  @override
  Future<void> unregister(String token) async {
    log.add('unregister:$token');
  }
}

class FakeOwnerStore implements PushStore {
  FakeOwnerStore(this.backend, this.owner, this.credential);
  final FakeStore backend;
  final String owner;
  final String credential;
  @override
  Future<bool> enabled(String userId) {
    if (userId != owner) throw StateError('wrong owner');
    return backend.enabled(userId);
  }

  @override
  Future<void> setEnabled(bool value) => backend.setEnabled(value);
  @override
  Future<void> register(String token, String platform) async {
    await backend.register(token, platform);
    backend.owners[token] = owner;
  }

  @override
  Future<void> unregister(String token) async {
    if (!backend.validCredentials.contains(credential)) {
      throw StateError('expired credential');
    }
    if (backend.owners[token] == owner) {
      backend.owners.remove(token);
      await backend.unregister(token);
    }
  }
}

void main() {
  late FakeTransport transport;
  late FakeStore store;
  late PushLifecycle lifecycle;
  late List<PushStatus> statuses;
  PushLifecycle create({bool configured = true, bool supported = true}) =>
      PushLifecycle(
        transport: transport,
        store: store,
        platform: 'web',
        configured: configured,
        platformSupported: supported,
        onStatus: statuses.add,
      );
  setUp(() {
    transport = FakeTransport();
    store = FakeStore();
    statuses = [];
    lifecycle = create();
  });
  tearDown(() async {
    lifecycle.dispose();
    await transport.controller.close();
  });
  test(
    'missing config and unsupported platform never touch transport or store',
    () async {
      lifecycle = create(configured: false);
      await lifecycle.switchUser('a');
      await lifecycle.enable();
      expect(statuses.last, PushStatus.unconfigured);
      expect(store.log, isEmpty);
      expect(transport.prompts, 0);
      lifecycle.dispose();
      lifecycle = create(supported: false);
      await lifecycle.switchUser('a');
      expect(statuses.last, PushStatus.unsupported);
    },
  );
  test(
    'registration waits for active context and switching contexts never prompts or deletes',
    () async {
      await lifecycle.switchUser('a', contextAvailable: false);
      expect(statuses.last, PushStatus.contextRequired);
      expect(store.log, isEmpty);
      await lifecycle.setContextAvailable(true);
      expect(statuses.last, PushStatus.enabled);
      await lifecycle.setContextAvailable(true);
      expect(transport.prompts, 0);
      expect(transport.deletes, 0);
      await lifecycle.setContextAvailable(false);
      await lifecycle.refresh();
      expect(statuses.last, PushStatus.contextRequired);
      await lifecycle.setContextAvailable(true);
      expect(statuses.last, PushStatus.enabled);
    },
  );
  test('no unsolicited permission; denial is distinct', () async {
    transport.current = PushPermission.undecided;
    await lifecycle.switchUser('a');
    expect(statuses.last, PushStatus.permission);
    expect(transport.prompts, 0);
    transport.current = PushPermission.denied;
    await lifecycle.enable();
    expect(statuses.last, PushStatus.denied);
    expect(transport.prompts, 1);
    expect(store.log.where((x) => x.startsWith('register:')), isEmpty);
  });
  test(
    'opt-out blocks registration; explicit enable and disable persist preference',
    () async {
      store.preference = false;
      await lifecycle.switchUser('a');
      expect(statuses.last, PushStatus.disabled);
      expect(store.log, isNot(contains('register:token-a')));
      await lifecycle.enable();
      expect(statuses.last, PushStatus.enabled);
      await lifecycle.disable();
      expect(statuses.last, PushStatus.disabled);
      expect(store.preference, false);
      expect(store.log, contains('unregister:token-a'));
    },
  );
  test(
    'token rotation unregisters old token and refresh obtains current token',
    () async {
      await lifecycle.switchUser('a');
      transport.controller.add('token-b');
      await Future<void>.delayed(Duration.zero);
      await lifecycle.refresh();
      expect(store.log, contains('unregister:token-a'));
      transport.value = 'token-c';
      await lifecycle.refresh();
      expect(store.log, contains('register:token-c'));
    },
  );
  test(
    'logout refreshes expired captured credential for the same owner',
    () async {
      await lifecycle.switchUser('a');
      store.validCredentials.remove('jwt-a');
      store.credential = 'jwt-a-refreshed';
      store.validCredentials.add(store.credential);
      await lifecycle.beforeLogout();
      expect(store.owners, isEmpty);
      expect(store.log, contains('unregister:token-a'));
    },
  );
  test(
    'logout and account swap serialize behind pending registration',
    () async {
      store.pending = Completer<void>();
      final first = lifecycle.switchUser('a');
      while (!store.log.contains('register:token-a')) {
        await Future<void>.delayed(Duration.zero);
      }
      store.caller = 'b';
      final swap = lifecycle.switchUser('b');
      store.pending!.complete();
      await first;
      await swap;
      expect(store.owners['token-a'], 'b');
      expect(transport.deletes, greaterThan(0));
      expect(
        store.log.indexOf('unregister:token-a'),
        lessThan(store.log.lastIndexOf('register:token-a')),
      );
      await lifecycle.beforeLogout();
      expect(store.log.last, 'unregister:token-a');
    },
  );
  test(
    'revoked permission clears registration and prevents rotation; opt-out remains possible',
    () async {
      await lifecycle.switchUser('a');
      transport.current = PushPermission.denied;
      await lifecycle.refresh();
      expect(statuses.last, PushStatus.denied);
      expect(store.owners, isEmpty);
      final registrations = store.log
          .where((e) => e.startsWith('register:'))
          .length;
      transport.controller.add('rotated');
      await Future<void>.delayed(Duration.zero);
      expect(
        store.log.where((e) => e.startsWith('register:')).length,
        registrations,
      );
      await lifecycle.disable();
      expect(store.preference, false);
    },
  );
  test('rotation rechecks account preference and permission', () async {
    await lifecycle.switchUser('a');
    store.preference = false;
    transport.controller.add('rotated');
    await Future<void>.delayed(Duration.zero);
    expect(statuses.last, PushStatus.disabled);
    expect(store.owners, isEmpty);
    expect(store.log, isNot(contains('register:rotated')));
  });
  test('errors surface without claiming enabled and allow retry', () async {
    store.fail = true;
    await lifecycle.switchUser('a');
    expect(statuses.last, PushStatus.error);
    store.fail = false;
    await lifecycle.refresh();
    expect(statuses.last, PushStatus.enabled);
  });
  test('MFA challenge or pending password suppresses registration', () {
    const user = User(
      id: 'id',
      fullName: 'Ana',
      email: 'a@example.test',
      initials: 'A',
    );
    const access = AccessContext(role: Role.funcionario, companyName: 'C');
    expect(notificationContextKey(null), isNull);
    expect(
      notificationContextKey(
        const AppSession(user: user, contexts: [], needsMfa: true),
      ),
      isNull,
    );
    expect(
      notificationContextKey(
        const AppSession(user: user, contexts: [], needsPassword: true),
      ),
      isNull,
    );
    expect(
      notificationContextKey(const AppSession(user: user, contexts: [])),
      isNull,
    );
    expect(
      notificationContextKey(
        const AppSession(
          user: user,
          contexts: [access],
          active: access,
          needsMfa: true,
        ),
      ),
      isNull,
    );
    expect(
      notificationContextKey(
        const AppSession(user: user, contexts: [access], active: access),
      ),
      'funcionario:null',
    );
  });
  test('config validates platform-specific Firebase and VAPID shapes', () {
    final key = 'AIza${'a' * 35}';
    final vapid = 'B${'a' * 86}';
    expect(
      validFirebaseConfig(
        apiKey: key,
        appId: '1:123456:web:abcdef1234567890',
        senderId: '123456',
        projectId: 'project-123',
        vapid: vapid,
        web: true,
      ),
      isTrue,
    );
    expect(
      validFirebaseConfig(
        apiKey: key,
        appId: '1:123456:android:abcdef1234567890',
        senderId: '123456',
        projectId: 'project-123',
        vapid: '',
        web: true,
      ),
      isFalse,
    );
    expect(
      validFirebaseConfig(
        apiKey: 'fake',
        appId: 'bad',
        senderId: 'x',
        projectId: 'x',
        vapid: '',
        web: false,
      ),
      isFalse,
    );
  });
}
