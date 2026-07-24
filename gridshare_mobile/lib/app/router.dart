import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/models.dart';
import '../data/providers.dart';
import '../features/auth/clerk_auth_screen.dart';
import '../features/wallet/topup_sheet.dart';
import '../features/home/home_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/payment/payment_sheet.dart';
import '../features/charging/charging_screen.dart';
import '../features/auth/splash_screen.dart';

/// Route table. Screens receive their data via `extra` (Session/Outlet).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loggedIn = ref.read(currentUserProvider) != null;
      final location = state.matchedLocation;

      // Allow SplashScreen to perform its 3s async restore & redirect
      if (location == '/splash') return null;

      if (!loggedIn && !location.startsWith('/auth')) return '/auth';
      if (loggedIn && location.startsWith('/auth')) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth', builder: (_, __) => const ClerkAuthScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/scan',
        builder: (_, state) => ScanScreen(outlet: state.extra as Outlet?),
      ),
      GoRoute(
        path: '/pay',
        builder: (_, state) => PaymentSheet(outlet: state.extra as Outlet),
      ),
      GoRoute(
        path: '/wallet/topup',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TopUpSheet(userId: extra?['userId'] ?? 'user_1');
        },
      ),
      GoRoute(
        path: '/charging',
        builder: (_, state) => ChargingScreen(session: state.extra as Session),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const HomeScreen()),
    ],
  );
});