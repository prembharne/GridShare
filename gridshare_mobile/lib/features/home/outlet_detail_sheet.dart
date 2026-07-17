import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../core/utils/currency.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

/// Bottom sheet showing outlet detail + "Start charging" CTA → navigates to payment.
class OutletDetailSheet extends ConsumerWidget {
  final Outlet outlet;
  const OutletDetailSheet({super.key, required this.outlet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.rXl)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: GradientText(outlet.name,
                    style: AppTextStyles.heading,
                    shimmer: false),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: outlet.available ? AppColors.accentSoft : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Text(
                  outlet.available ? 'Available' : 'In use',
                  style: AppTextStyles.label.copyWith(
                    color: outlet.available ? AppColors.accent : AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Hosted by ${outlet.hostName} · ★ ${outlet.rating.toStringAsFixed(1)} · '
              '${outlet.distanceKm.toStringAsFixed(1)} km', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.lg),
          GlassCard(
            glow: true,
            glowColor: AppColors.accent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rate', style: AppTextStyles.label),
                Text('${Compliance.rupees(outlet.ratePerKwh)} / kWh',
                    style: AppTextStyles.title.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Billed as ${Compliance.serviceLabel}.', style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.xl),
          Consumer(
            builder: (_, ref, __) {
              final user = ref.watch(currentUserProvider);
              final balance = (user?.walletBalanceCredits ?? 0);
              return Column(
                children: [
                  AppButton(
                    label: 'Start charging',
                    width: double.infinity,
                    icon: Icons.qr_code_2_rounded,
                    onPressed: outlet.available
                        ? () {
                            context.pop();
                            context.push('/pay', extra: outlet);
                          }
                        : null,
                  ),
                  if (balance < 20) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.accent),
                      label: const Text('Top up wallet', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                      onPressed: () {
                        context.pop();
                        context.push('/wallet/topup', extra: {'userId': user?.id ?? 'user_1'});
                      },
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
