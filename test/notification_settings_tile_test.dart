import 'package:educador/app/theme.dart';
import 'package:educador/data/repositories/notification_controller.dart';
import 'package:educador/features/notifications/notification_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Notifications extends NotificationController {
  _Notifications(this.initial);
  final PushStatus initial;
  int retries = 0;
  int enables = 0;
  int disables = 0;
  @override
  PushStatus build() {
    ref.onDispose(events.close);
    return initial;
  }

  @override
  Future<void> refresh() async {
    retries++;
  }

  @override
  Future<void> enable() async {
    enables++;
  }

  @override
  Future<void> disable() async {
    disables++;
  }
}

void main() {
  testWidgets(
    'token failures explain browser registration rather than claiming preference save failed',
    (tester) async {
      final notifier = _Notifications(PushStatus.error)
        ..lastFailure = const PushFailure(
          PushStep.token,
          'token-subscribe-failed',
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationControllerProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: NotificationSettingsTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Não foi possível registrar as notificações neste navegador.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Não foi possível atualizar. Tente novamente.'),
        findsNothing,
      );
      await tester.tap(find.text('Tentar novamente'));
      expect(notifier.retries, 1);
    },
  );
  for (final status in [
    PushStatus.error,
    PushStatus.enabled,
    PushStatus.denied,
    PushStatus.loading,
    PushStatus.unconfigured,
  ]) {
    testWidgets(
      'notification row uses account styling at 320px: ${status.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final notifier = _Notifications(status);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              notificationControllerProvider.overrideWith(() => notifier),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: NotificationSettingsTile(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Card), findsNothing);
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(SwitchListTile),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, AppColors.surface);
        expect(material.shape, isA<RoundedRectangleBorder>());
        expect(
          (material.shape! as RoundedRectangleBorder).side.color,
          AppColors.border,
        );
        expect(tester.takeException(), isNull);
        final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        if (status == PushStatus.error) {
          final semantics = tester.ensureSemantics();
          expect(find.bySemanticsLabel('Tentar novamente'), findsOneWidget);
          await tester.tap(find.text('Tentar novamente'));
          expect(notifier.retries, 1);
          expect(notifier.enables, 0);
          expect(notifier.disables, 0);
          semantics.dispose();
        } else if (status == PushStatus.enabled ||
            status == PushStatus.denied) {
          tile.onChanged!(false);
          expect(notifier.disables, 1);
        } else {
          expect(tile.onChanged, isNull);
        }
      },
    );
  }
}
