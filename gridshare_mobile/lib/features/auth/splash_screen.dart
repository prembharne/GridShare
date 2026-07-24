import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final authService = ref.read(authServiceProvider);
      // Timeout after 3 seconds in case network is unreachable
      final user = await authService.tryRestoreSession().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );

      if (!mounted) return;

      if (user != null) {
        ref.read(currentUserProvider.notifier).state = user;
        context.go('/');
      } else {
        context.go('/auth');
      }
    } catch (_) {
      if (mounted) context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: AppColors.accentGlow,
                shape: BoxShape.circle,
                boxShadow: AppSpacing.glow(color: AppColors.accent),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: AppColors.background,
                size: 56,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const CircularProgressIndicator(
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

