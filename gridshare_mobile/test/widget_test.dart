// This is a basic Flutter widget test for GridShare.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridshare_mobile/main.dart';
import 'package:gridshare_mobile/features/auth/clerk_auth_screen.dart';

void main() {
  testWidgets('GridShare app builds without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: GridShareApp()));

    // Verify that the app loads the clerk auth screen initially.
    expect(find.byType(ClerkAuthScreen), findsOneWidget);
  });
}