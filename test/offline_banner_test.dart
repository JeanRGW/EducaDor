import 'dart:async';

import 'package:educador/app/offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only browser offline hint shows banner; reconnect removes it', (
    tester,
  ) async {
    final changes = StreamController<bool>();
    addTearDown(changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineBanner(
          initial: false,
          changes: changes.stream,
          child: const Text('Shell'),
        ),
      ),
    );
    expect(find.byIcon(Icons.wifi_off), findsNothing);
    changes.add(true);
    await tester.pump();
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(find.textContaining('Sem conexão'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    changes.add(false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.wifi_off), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(changes.hasListener, isFalse);
  });

  testWidgets('native fallback never infers offline from application errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OfflineBanner(child: Text('Erro de autenticação')),
      ),
    );
    expect(find.byIcon(Icons.wifi_off), findsNothing);
  });
}
