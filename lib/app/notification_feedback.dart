import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/router.dart';
import '../data/repositories/notification_controller.dart';
import '../data/session/session_controller.dart';

class NotificationFeedback extends ConsumerStatefulWidget {
  final Widget child;
  const NotificationFeedback({super.key, required this.child});

  @override
  ConsumerState<NotificationFeedback> createState() =>
      _NotificationFeedbackState();
}

class _NotificationFeedbackState extends ConsumerState<NotificationFeedback> {
  StreamSubscription<bool>? _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = ref
        .read(notificationControllerProvider.notifier)
        .events
        .stream
        .listen((opened) {
          if (!mounted) return;
          if (opened) {
            final session = ref.read(sessionProvider).value;
            if (session != null) ref.read(routerProvider).go(session.homePath);
          } else {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Há uma atualização no aplicativo.'),
              ),
            );
          }
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
