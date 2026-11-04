import 'package:flutter/material.dart';
import 'notification_settings_tile.dart';

Future<void> showNotificationSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: NotificationSettingsTile(),
        ),
      ),
    );
