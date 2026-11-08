import 'package:educador/data/repositories/notification_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<String> logs;
  late DebugPrintCallback original;
  setUp(() {
    logs = [];
    original = debugPrint;
    debugPrint = (String? text, {int? wrapWidth}) {
      if (text != null) logs.add(text);
    };
  });
  tearDown(() => debugPrint = original);

  test(
    'production diagnostics contain only stage and SDK code, never exception details',
    () {
      final failure = reportPushFailure(
        PushStep.token,
        FirebaseException(
          plugin: 'firebase_messaging',
          code: 'token-subscribe-failed',
          message:
              'private-token and https://private.example/?authorization=private-jwt',
        ),
      );
      expect(failure.step, PushStep.token);
      expect(failure.code, 'token-subscribe-failed');
      expect(logs, [
        'EducaDor notifications: stage=token, code=token-subscribe-failed',
      ]);
      expect(logs.join(), isNot(contains('private')));
      expect(logs.join(), isNot(contains('https:')));
    },
  );

  test('malformed error codes are discarded rather than printed', () {
    final failure = reportPushFailure(
      PushStep.tokenRegistration,
      PlatformException(
        code: 'error?token=private-token',
        message: 'private message',
      ),
    );
    expect(failure.code, 'unknown-error');
    expect(
      logs.single,
      'EducaDor notifications: stage=tokenRegistration, code=unknown-error',
    );
  });

  test('database and local failures have safe useful codes', () {
    expect(
      reportPushFailure(
        PushStep.tokenRegistration,
        const PostgrestException(message: 'private', code: '42501'),
      ).code,
      '42501',
    );
    expect(
      reportPushFailure(PushStep.token, StateError('private')).code,
      'invalid-state',
    );
    expect(logs.join(), isNot(contains('private')));
  });
}
