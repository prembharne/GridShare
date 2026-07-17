import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// The ONLY place red breaks the palette — a Safety-Trip alert. Registers as serious.
class SafetyBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onDismiss;

  const SafetyBanner({
    super.key,
    this.title = 'Safety Trip',
    this.message = 'Abnormal current detected. Power cut automatically.',
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppSpacing.rMd),
        border: Border.all(color: AppColors.danger.withValues(alpha:0.5), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.title.copyWith(color: AppColors.danger)),
                const SizedBox(height: 4),
                Text(message, style: AppTextStyles.body.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.danger),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
