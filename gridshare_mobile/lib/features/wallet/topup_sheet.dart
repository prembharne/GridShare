import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../data/providers.dart';

/// Top-up sheet — amount picker + Razorpay checkout.
class TopUpSheet extends ConsumerStatefulWidget {
  final String userId;
  const TopUpSheet({super.key, required this.userId});

  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<TopUpSheet> {
  int _amount = 100;
  bool _loading = false;

  final List<int> _presets = [50, 100, 200, 500, 1000];

  Future<void> _topUp() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final order = await api.createTopUpOrder(
        amountCredits: _amount,
        userId: widget.userId,
        idempotencyKey: 'topup_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // TODO: Launch Razorpay checkout with order.orderId, order.keyId, order.amountCredits
      // On success, Razorpay webhook will mint credits on-chain.
      // For demo, simulate webhook success:
      final balance = await api.getBalance(userId: widget.userId);

      if (!mounted) return;
      ref.read(currentUserProvider.notifier).state = (ref.read(currentUserProvider)!.copyWith(
        walletBalanceCredits: balance.balanceCredits,
      ));
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('₹$_amount credits added! Balance: ${balance.balanceCredits}'), backgroundColor: AppColors.accent),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: _loading ? null : () => Navigator.pop(context),
        ),
        title: const Text('Top Up Wallet', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeSlide(
                delay: const Duration(milliseconds: 80),
                child: GlassCard(
                  glow: true,
                  glowColor: AppColors.accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GradientText('Add Credits', style: AppTextStyles.heading, shimmer: false),
                      const SizedBox(height: 4),
                      const Text('1 credit = ₹1', style: AppTextStyles.caption),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GradientText(_amount.toString(),
                              style: AppTextStyles.display, shimmer: false),
                          const SizedBox(width: 6),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Text('credits', style: TextStyle(fontSize: 20, color: AppColors.accent, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text('≈ ₹$_amount', style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Choose amount', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                children: _presets
                    .map((p) => ChoiceChip(
                          label: Text('₹$p'),
                          selected: _amount == p,
                          onSelected: _loading ? null : (_) => setState(() => _amount = p),
                          selectedColor: AppColors.accent,
                          backgroundColor: AppColors.surfaceHigh,
                          labelStyle: TextStyle(
                            color: _amount == p ? AppColors.background : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                        ))
                    .toList(),
              ),
              const Spacer(),
              FadeSlide(
                delay: const Duration(milliseconds: 200),
                child: AppButton(
                  label: _loading ? 'Creating order…' : 'Pay with UPI',
                  loading: _loading,
                  width: double.infinity,
                  icon: Icons.account_balance_wallet_rounded,
                  onPressed: _loading ? null : _topUp,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Secured by Razorpay · credits minted on Stellar testnet.',
                  style: AppTextStyles.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}