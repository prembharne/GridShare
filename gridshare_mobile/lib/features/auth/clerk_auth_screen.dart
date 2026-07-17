// Copyright 2024 GridShare. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../core/shaders/shader_canvas.dart';
import '../../data/providers.dart';

/// Clerk authentication screen using native Android View (Clerk SignInOrUpView)
/// This replaces the OTP-based auth with Clerk's Google One Tap + email/password flow
class ClerkAuthScreen extends ConsumerStatefulWidget {
  const ClerkAuthScreen({super.key});

  @override
  ConsumerState<ClerkAuthScreen> createState() => _ClerkAuthScreenState();
}

class _ClerkAuthScreenState extends ConsumerState<ClerkAuthScreen> {
  final _channel = const MethodChannel('gridshare_mobile/clerk_auth');
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSignInComplete':
        _onSignInComplete(call.arguments as Map<dynamic, dynamic>);
        break;
      case 'onSignInFailed':
        _onSignInFailed(call.arguments as String);
        break;
      case 'onSignUpComplete':
        _onSignInComplete(call.arguments as Map<dynamic, dynamic>);
        break;
      case 'onSignUpFailed':
        _onSignInFailed(call.arguments as String);
        break;
    }
  }

  void _onSignInComplete(Map<dynamic, dynamic> args) async {
    final accessToken = args['accessToken'] as String?;
    final userId = args['userId'] as String?;

    if (accessToken != null && userId != null) {
      try {
        // Store token and get user profile with wallet balance
        final authService = ref.read(authServiceProvider);
        final secureStorage = ref.read(secureStorageProvider);

        await secureStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: '', // Clerk handles refresh internally
        );

        // Get user profile from backend using Clerk token
        final response = await authService.fetchUserWithBalance(userId);

        if (mounted) {
          ref.read(currentUserProvider.notifier).state = response;
          context.go('/');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to sync user: $e';
          });
        }
      }
    }
  }

  void _onSignInFailed(String error) {
    if (mounted) {
      setState(() {
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Layered living background: aurora field + drifting spark dust.
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.aurora(),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.spark(color: AppColors.accent, density: 0.5),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          // Floating accent orb for depth.
          Positioned(
            top: -60,
            right: -40,
            child: PulseGlow(
              color: AppColors.accent,
              maxBlur: 90,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: PulseGlow(
              color: AppColors.accentAlt,
              maxBlur: 110,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentAlt.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          // Legibility veil so content pops over the shader.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.background.withValues(alpha: 0.2),
                    AppColors.background.withValues(alpha: 0.78),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.xxxl),
                            FadeSlide(
                              delay: const Duration(milliseconds: 80),
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                                  boxShadow: AppSpacing.glowSoft(),
                                ),
                                child: const Icon(Icons.bolt_rounded, color: AppColors.accent, size: 28),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FadeSlide(
                              delay: const Duration(milliseconds: 160),
                              child: GradientText(
                                'Welcome to\nGridShare',
                                style: AppTextStyles.display,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FadeSlide(
                              delay: const Duration(milliseconds: 220),
                              child: const Text('Peer-to-peer EV charging. Tap a plug, pay, charge.',
                                  style: AppTextStyles.body),
                            ),
                            const Spacer(),
                            // Clerk native sign-in/up view
                            FadeSlide(
                              delay: const Duration(milliseconds: 300),
                              child: SizedBox(
                                height: 380,
                                child: _buildClerkView(),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (_error != null)
                              FadeSlide(
                                delay: const Duration(milliseconds: 380),
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(child: Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.danger))),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: AppSpacing.md),
                            FadeSlide(
                              delay: const Duration(milliseconds: 440),
                              child: const Text('By continuing you agree to our Infrastructure Facility & Leasing terms.',
                                  style: AppTextStyles.caption),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClerkView() {
    // Use PlatformView to embed the native Android Clerk SignInOrUpView
    if (Theme.of(context).platform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'gridshare_mobile/clerk_signin',
        layoutDirection: TextDirection.ltr,
        creationParams: <String, dynamic>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }

    // Fallback for iOS/Web - show a placeholder or use a different approach
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text('Clerk Auth requires Android', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Continue with Google (Mock)',
            width: 280,
            onPressed: _mockSignIn,
            icon: Icons.g_mobiledata_rounded,
          ),
        ],
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    // The Android view is created, we can send initialization params if needed
    _channel.invokeMethod('initialize', {'viewId': id});
  }

  void _mockSignIn() async {
    // For iOS/Web testing - mock a sign in
    try {
      // Use test user
      final authService = ref.read(authServiceProvider);
      final secureStorage = ref.read(secureStorageProvider);

      await secureStorage.saveTokens(
        accessToken: 'mock_clerk_token_user_1',
        refreshToken: '',
      );

      final response = await authService.fetchUserWithBalance('user_1');
      ref.read(currentUserProvider.notifier).state = response;
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Mock sign in failed: $e';
        });
      }
    }
  }
}