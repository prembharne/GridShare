import 'package:flutter/material.dart';
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

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phone = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim().isEmpty ? '9579083283' : _phone.text.trim();
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).sendOtp(phone);
      if (!mounted) return;
      context.push('/auth/otp', extra: phone);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send OTP: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                  FadeSlide(
                    delay: const Duration(milliseconds: 300),
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
                      decoration: const InputDecoration(
                        prefixText: '+91  ',
                        prefixStyle: TextStyle(color: AppColors.textSecondary, fontSize: 18),
                        hintText: 'Phone number',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FadeSlide(
                    delay: const Duration(milliseconds: 380),
                    child: AppButton(
                      label: 'Send OTP',
                      loading: _loading,
                      width: double.infinity,
                      onPressed: _sendOtp,
                      icon: Icons.arrow_forward_rounded,
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
        ],
      ),
    );
  }
}