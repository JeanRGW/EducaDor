import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:educador/app/app.dart';

void main() {
  testWidgets('app boots: splash advances to welcome', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EducaDorApp()));

    // Splash screen shows the logo lockup.
    expect(find.text('EducaDOR'), findsWidgets);

    // Let the splash timer fire and the route settle on /welcome.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('BEM-VINDO!'), findsOneWidget);
  });
}
