import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  final SupabaseClient client;
  NotificationRepository(this.client);

  Future<bool> enabled(String userId) async {
    final row = await client
        .from('notification_preferences')
        .select('push_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['push_enabled'] as bool? ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    await client.rpc('set_push_enabled', params: {'p_enabled': enabled});
  }

  Future<void> register(String token, String platform) async {
    await client.rpc(
      'register_fcm_token',
      params: {'p_token': token, 'p_platform': platform},
    );
  }

  Future<void> unregister(String token) async {
    await client.rpc('unregister_fcm_token', params: {'p_token': token});
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
