import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Empty / error / offline states with a short illustration, never a blank screen.
class StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  factory StateView.empty({VoidCallback? onAction}) => StateView(
        icon: Icons.electrical_services_outlined,
        title: 'No outlets nearby',
        message: 'We couldn\'t find any charging points around you yet. Try another area.',
        actionLabel: 'Refresh',
        onAction: onAction,
      );

  factory StateView.offline({VoidCallback? onAction}) => StateView(
        icon: Icons.cloud_off_outlined,
        title: 'You\'re offline',
        message: 'GridShare works in degraded mode — your last session is cached locally.',
        actionLabel: 'Retry',
        onAction: onAction,
      );

  factory StateView.error({VoidCallback? onAction}) => StateView(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message: 'The network hiccuped. This is your graceful-degradation moment.',
        actionLabel: 'Try again',
        onAction: onAction,
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh,
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Icon(icon, size: 40, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: AppTextStyles.heading, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
                ),
                child: Text(actionLabel!, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
