// Copyright 2024 GridShare. All rights reserved.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/animations/animated_counter.dart';
import '../../data/providers.dart';

/// Clerk authentication screen — Premium Dark Theme (unified with app design system).
/// Navy base + ambient cyan/emerald orbs + frosted glass login card.
class ClerkAuthScreen extends ConsumerStatefulWidget {
  const ClerkAuthScreen({super.key});

  @override
  ConsumerState<ClerkAuthScreen> createState() => _ClerkAuthScreenState();
}

class _ClerkAuthScreenState extends ConsumerState<ClerkAuthScreen> {
  final _channel = const MethodChannel('gridshare_mobile/clerk_auth');
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  // Google Sign-In instance configured with Web Client ID (serverClientId)
  static final _googleSignIn = GoogleSignIn(
    serverClientId: '959322421139-ljm30f0l25p7lor9gnqqi97sfviegqna.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );



  bool _isLoading = false;
  bool _otpSent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onSignInComplete':
      case 'onSignUpComplete':
        final args = call.arguments as Map<dynamic, dynamic>;
        final accessToken = args['accessToken'] as String?;
        final userId = args['userId'] as String?;
        if (accessToken != null && userId != null) {
          await _completeLogin(accessToken: accessToken, userId: userId);
        }
        break;
      case 'onSignInFailed':
      case 'onSignUpFailed':
        setState(() { _error = call.arguments as String; _isLoading = false; });
        break;
    }
  }

  Future<void> _completeLogin({required String accessToken, required String userId}) async {
    try {
      final secureStorage = ref.read(secureStorageProvider);
      final authService = ref.read(authServiceProvider);
      await secureStorage.saveTokens(accessToken: accessToken, refreshToken: '');
      final user = await authService.fetchUserWithBalance(userId);
      if (mounted) {
        ref.read(currentUserProvider.notifier).state = user;
        context.go('/');
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Login failed: $e'; _isLoading = false; });
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter your phone number.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      await authService.sendOtp(phone);
      if (mounted) setState(() { _otpSent = true; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _isLoading = false; });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() => _error = 'Please enter the OTP.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final authService = ref.read(authServiceProvider);
      final phone = _phoneController.text.trim();
      final response = await authService.verifyOtp(phone, otp);
      if (response.accessToken != null && response.user != null) {
        if (mounted) {
          ref.read(currentUserProvider.notifier).state = response.user!;
          context.go('/');
        }
      } else {
        if (mounted) setState(() { _error = 'Verification failed. Try again.'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _isLoading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // Sign out first to show account picker every time
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final authService = ref.read(authServiceProvider);
      final response = await authService.signInWithGoogle(
        googleId: googleUser.id,
        email: googleUser.email,
        name: googleUser.displayName ?? googleUser.email,
      );
      if (response.user != null && mounted) {
        ref.read(currentUserProvider.notifier).state = response.user!;
        context.go('/');
      } else {
        if (mounted) setState(() { _error = 'Google sign-in failed. Try again.'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Google sign-in error: ${e.toString().replaceFirst('Exception: ', '')}'; _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. Deep navy base
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.background),
            ),
          ),
          // 2. Diffused ambient accent orbs (cyan + emerald) for organic depth
          Positioned(
            top: -90, right: -90,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withOpacity(0.14), // cyan glow
              ),
            ),
          ),
          Positioned(
            bottom: -110, left: -70,
            child: Container(
              width: 340, height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.hostAccent.withOpacity(0.10), // emerald glow
              ),
            ),
          ),
          // 3. Main Content
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: LayoutBuilder(builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.xxl),
                            
                            // Header Logo Icon
                            FadeSlide(
                              delay: const Duration(milliseconds: 80),
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  gradient: AppColors.accentGlow,
                                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                                  boxShadow: AppSpacing.glow(color: AppColors.accent),
                                ),
                                child: const Icon(Icons.bolt_rounded, color: AppColors.background, size: 28),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            
                            // Clean premium dark slate typography
                            FadeSlide(
                              delay: const Duration(milliseconds: 160),
                              child: const Text(
                                'Welcome to\nGridShare',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.displayFamily,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  height: 1.15,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FadeSlide(
                              delay: const Duration(milliseconds: 220),
                              child: const Text(
                                'Peer-to-peer EV charging. Tap a plug, pay, charge.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),
  
                            // Clean Floating White Card
                            FadeSlide(
                              delay: const Duration(milliseconds: 300),
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: AppSpacing.glow(
                                    color: AppColors.accent,
                                    strength: 0.08,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // Google Button
                                    _buildGoogleButton(),
                                    const SizedBox(height: AppSpacing.lg),
  
                                    // Divider
                                    Row(children: [
                                      const Expanded(child: Divider(color: AppColors.border)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                        child: const Text(
                                          'or phone number',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ),
                                      const Expanded(child: Divider(color: AppColors.border)),
                                    ]),
                                    const SizedBox(height: AppSpacing.lg),
  
                                    // Phone input
                                    _buildTextField(
                                      controller: _phoneController,
                                      hint: '+91 9876543210',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      enabled: !_otpSent,
                                    ),
  
                                    // OTP input
                                    if (_otpSent) ...[
                                      const SizedBox(height: AppSpacing.md),
                                      _buildTextField(
                                        controller: _otpController,
                                        hint: 'Enter 6-digit OTP',
                                        icon: Icons.pin_outlined,
                                        keyboardType: TextInputType.number,
                                      ),
                                    ],
  
                                    const SizedBox(height: AppSpacing.xl),
  
                                    // Action Button
                                    _buildActionButton(),
  
                                    if (_otpSent) ...[
                                      const SizedBox(height: AppSpacing.md),
                                      GestureDetector(
                                        onTap: () => setState(() { _otpSent = false; _otpController.clear(); _error = null; }),
                                        child: const Text(
                                          '← Change number',
                                          style: TextStyle(
                                            color: AppColors.accent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
  
                            if (_error != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              FadeSlide(
                                delay: Duration.zero,
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ],
  
                            const SizedBox(height: AppSpacing.xxxl),
                            FadeSlide(
                              delay: const Duration(milliseconds: 400),
                              child: const Center(
                                child: Text(
                                  'By continuing you agree to our Infrastructure Terms.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: AppColors.background.withValues(alpha: 0.6),
                child: const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoogleButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _signInWithGoogle,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Styled colored G icon
            Image.network(
              'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1024px-Google_%22G%22_logo.svg.png',
              width: 18,
              height: 18,
              errorBuilder: (_, __, ___) => const Text('G', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? AppColors.surfaceHigh : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        enabled: enabled,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: enabled ? AppColors.textPrimary : AppColors.textMuted,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.transparent,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: AppSpacing.md),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return AppButton(
      width: double.infinity,
      loading: _isLoading,
      label: _isLoading
          ? (_otpSent ? 'Verifying…' : 'Sending OTP…')
          : (_otpSent ? 'Verify OTP' : 'Send OTP'),
      icon: _otpSent ? Icons.check_circle_outline : Icons.arrow_forward_rounded,
      onPressed: _isLoading ? null : (_otpSent ? _verifyOtp : _sendOtp),
    );
  }
}

/// Full-screen wrapper for the native Clerk AuthView.
/// Handles Google Sign-In and all Clerk auth methods.
/// Navigates to '/' on successful sign-in.
class _ClerkNativeSignInScreen extends StatefulWidget {
  const _ClerkNativeSignInScreen();

  @override
  State<_ClerkNativeSignInScreen> createState() => _ClerkNativeSignInScreenState();
}

class _ClerkNativeSignInScreenState extends State<_ClerkNativeSignInScreen> {
  final _channel = const MethodChannel('gridshare_mobile/clerk_auth');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onSignInComplete':
      case 'onSignUpComplete':
        // Pop the sign-in screen and go to home
        if (mounted) {
          Navigator.of(context).pop();
          context.go('/');
        }
        break;
      case 'onSignInFailed':
      case 'onSignUpFailed':
        if (mounted) {
          Navigator.of(context).pop();
        }
        break;
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Sign in with Google',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: const AndroidView(
        viewType: 'gridshare_mobile/clerk_signin',
        layoutDirection: TextDirection.ltr,
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}