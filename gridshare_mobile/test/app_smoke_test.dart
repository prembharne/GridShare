import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridshare_mobile/main.dart';
import 'package:gridshare_mobile/features/auth/clerk_auth_screen.dart';

void main() {
  testWidgets('Clerk auth screen loads', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GridShareApp()));

    // Advance timers to let animations start
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Clerk auth screen loads
    expect(find.textContaining('Welcome to'), findsOneWidget);
    expect(find.byType(ClerkAuthScreen), findsOneWidget);
  });
}
