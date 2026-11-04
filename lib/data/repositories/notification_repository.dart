import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_lifecycle.dart';

class NotificationRepository implements PushStore {
  final SupabaseClient client;
  NotificationRepository(this.client);

  @override
  Future<bool> enabled(String userId) async {
    final row = await client
        .from('notification_preferences')
        .select('push_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['push_enabled'] as bool? ?? true;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await client.rpc('set_push_enabled', params: {'p_enabled': enabled});
  }

  @override
  Future<void> register(String token, String platform) async {
    await client.rpc(
      'register_fcm_token',
      params: {'p_token': token, 'p_platform': platform},
    );
  }

  @override
  Future<void> unregister(String token) async {
    await client.rpc('unregister_fcm_token', params: {'p_token': token});
  }
}

Future<void> sendCertificateIssued(
  SupabaseClient client,
  Object? response,
) async {
  if (response is! Map ||
      response['created'] != true ||
      response['id'] is! String) {
    return;
  }
  try {
    await client.functions.invoke(
      'push-on-assign',
      body: {'event': 'certificate_issued', 'certificate_id': response['id']},
    );
  } catch (_) {
    // Certificate issuance remains successful even when push fails.
  }
}

Future<void> sendCourseAvailable(
  SupabaseClient client,
  String courseId, {
  String? companyId,
}) async {
  try {
    await client.functions.invoke(
      'push-on-assign',
      body: {
        'event': 'course_available',
        'course_id': courseId,
        'company_id': ?companyId,
      },
    );
  } catch (_) {
    // Push is best effort and must not roll back the content mutation.
  }
}
