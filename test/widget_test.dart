import 'package:flutter_test/flutter_test.dart';

import 'package:admin_desktop/main.dart';

void main() {
  testWidgets('HYG admin app starts with splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HygAdminApp());

    expect(find.text('HYG HR Admin'), findsOneWidget);
    expect(find.text('Preparing desktop workspace'), findsOneWidget);
  });

  testWidgets('HYG admin login appears after splash', (WidgetTester tester) async {
    await tester.pumpWidget(const HygAdminApp());
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Secure Desktop Portal'), findsOneWidget);
  });
}
