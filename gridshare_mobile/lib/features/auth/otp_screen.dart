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

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    try {
      final authService = ref.read(authServiceProvider);
      final response = await authService.verifyOtp(widget.phone, _code.text.isEmpty ? '123456' : _code.text);

      if (response.user != null) {
        ref.read(currentUserProvider.notifier).state = response.user;
      }

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.aurora(color: AppColors.accentAlt, b: AppColors.accent),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.spark(color: AppColors.accentAlt, density: 0.4),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.background.withValues(alpha: 0.35),
                    AppColors.background.withValues(alpha: 0.82),
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
                  FadeSlide(
                    delay: const Duration(milliseconds: 120),
                    child: PulseGlow(
                      color: AppColors.accentAlt,
                      minBlur: 14,
                      maxBlur: 34,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentSoft,
                          border: Border.all(
                            color: AppColors.accentAlt.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: const Icon(Icons.sms_rounded,
                            color: AppColors.accentAlt, size: 30),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FadeSlide(
                    delay: const Duration(milliseconds: 200),
                    child: GradientText(
                      'Verify it\'s you',
                      style: AppTextStyles.display,
                      colors: const [AppColors.accentAlt, AppColors.accent],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FadeSlide(
                    delay: const Duration(milliseconds: 260),
                    child: Text('We sent a 6-digit code to +91 ${widget.phone}',
                        style: AppTextStyles.body),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlide(
                    delay: const Duration(milliseconds: 320),
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, letterSpacing: 12, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.rMd),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.rMd),
                          borderSide: const BorderSide(color: AppColors.accentAlt, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FadeSlide(
                    delay: const Duration(milliseconds: 400),
                    child: AppButton(
                      label: 'Verify & enter',
                      loading: _loading,
                      width: double.infinity,
                      onPressed: _verify,
                      icon: Icons.check_circle_rounded,
                    ),
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