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

/// Session intent sheet — creates a charging session with locked deposit.
/// Replaces the old "PaymentSheet" per-session payment flow.
class SessionIntentSheet extends ConsumerStatefulWidget {
  final Outlet outlet;
  final String riderId;
  final String hostId;
  final int depositCredits;

  const SessionIntentSheet({
    super.key,
    required this.outlet,
    required this.riderId,
    required this.hostId,
    required this.depositCredits,
  });

  @override
  ConsumerState<SessionIntentSheet> createState() => _SessionIntentSheetState();
}

class _SessionIntentSheetState extends ConsumerState<SessionIntentSheet> {
  bool _creating = false;

  // Per-minute billing. The rider picks how long they want to charge; the
  // deposit is derived from rate × duration so nothing is over-locked.
  static const int _ratePerMinuteCredits = 2; // credits/minute service rate
  static const List<int> _durationOptions = [15, 30, 45, 60, 90];
  int _durationMinutes = 30;

  int get _depositForDuration => _ratePerMinuteCredits * _durationMinutes;

  Future<void> _createIntent() async {
    setState(() => _creating = true);
    try {
      final api = ref.read(apiServiceProvider);
      final session = await api.createIntent(
        riderId: widget.riderId,
        hostId: widget.hostId,
        outletId: widget.outlet.id,
        depositCredits: _depositForDuration,
        ratePerMinuteCredits: _ratePerMinuteCredits,
        selectedDurationMinutes: _durationMinutes,
        idempotencyKey:
            'intent_${widget.riderId}_${widget.outlet.id}_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;
      context.pop(session); // Return session to caller
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to create session: $e'),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
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
          onPressed: _creating ? null : () => context.pop(),
        ),
        title: const Text('Start Charging', style: AppTextStyles.title),
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
                      GradientText(widget.outlet.name,
                          style: AppTextStyles.heading, shimmer: false),
                      const SizedBox(height: 4),
                      const Text(Compliance.serviceLabel,
                          style: AppTextStyles.caption),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GradientText(_depositForDuration.toString(),
                              style:
                                  AppTextStyles.display.copyWith(fontSize: 48),
                              shimmer: false),
                          const SizedBox(width: 6),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Text('credits',
                                style: TextStyle(
                                    fontSize: 20,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                          '$_durationMinutes min · $_ratePerMinuteCredits credits/min',
                          style: AppTextStyles.caption),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Deposit is locked upfront and auto-stops after $_durationMinutes minutes. Unused credits are refunded when you stop.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Charging duration', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: _durationOptions.map((minutes) {
                  final selected = _durationMinutes == minutes;
                  return ChoiceChip(
                    label: Text('$minutes min'),
                    selected: selected,
                    onSelected: _creating
                        ? null
                        : (_) => setState(() => _durationMinutes = minutes),
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceHigh,
                    labelStyle: TextStyle(
                      color: selected
                          ? AppColors.background
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                  );
                }).toList(),
              ),
              const Spacer(),
              FadeSlide(
                delay: const Duration(milliseconds: 200),
                child: AppButton(
                  label:
                      _creating ? 'Creating session…' : 'Lock deposit & start',
                  loading: _creating,
                  width: double.infinity,
                  icon: Icons.lock_rounded,
                  onPressed: _creating ? null : _createIntent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Legacy payment sheet — kept for backwards compatibility during migration.
/// Shows wallet balance + top-up option, then creates session intent.
class PaymentSheet extends ConsumerStatefulWidget {
  final Outlet outlet;
  const PaymentSheet({super.key, required this.outlet});

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  int _depositAmount = 50;
  bool _paying = false;

  final List<int> _presets = [20, 50, 100, 200];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: _paying ? null : () => context.pop(),
        ),
        title: const Text('Start Charging', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Consumer(
                builder: (_, ref, __) {
                  final user = ref.watch(currentUserProvider);
                  return FadeSlide(
                    delay: const Duration(milliseconds: 80),
                    child: GlassCard(
                      glow: true,
                      glowColor: AppColors.accent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GradientText(widget.outlet.name,
                              style: AppTextStyles.heading, shimmer: false),
                          const SizedBox(height: 4),
                          const Text(Compliance.serviceLabel,
                              style: AppTextStyles.caption),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Wallet Balance',
                                      style: AppTextStyles.caption),
                                  GradientText(
                                    '${(user?.walletBalanceCredits ?? 0).toInt()} credits',
                                    style: AppTextStyles.display
                                        .copyWith(fontSize: 36),
                                    shimmer: true,
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: AppColors.accent),
                                label: const Text('Top Up',
                                    style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () => context.push('/wallet/topup',
                                    extra: {'userId': user?.id ?? 'user_1'}),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Deposit amount', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                children: _presets
                    .map((p) => ChoiceChip(
                          label: Text('${p.toInt()} credits'),
                          selected: _depositAmount == p,
                          onSelected: (_) => setState(() => _depositAmount = p),
                          selectedColor: AppColors.accent,
                          backgroundColor: AppColors.surfaceHigh,
                          labelStyle: TextStyle(
                            color: _depositAmount == p
                                ? AppColors.background
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.rPill),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  '≈ ${(_depositAmount / widget.outlet.ratePerKwh).toStringAsFixed(1)} kWh at ${widget.outlet.ratePerKwh.toInt()} credits/kWh',
                  style: AppTextStyles.caption),
              const Spacer(),
              Consumer(
                builder: (_, ref, __) {
                  final user = ref.watch(currentUserProvider);
                  final balance = (user?.walletBalanceCredits ?? 0);
                  final canAfford = balance >= _depositAmount;

                  return FadeSlide(
                    delay: const Duration(milliseconds: 200),
                    child: AppButton(
                      label: _paying
                          ? 'Creating session…'
                          : 'Lock deposit & start charging',
                      loading: _paying,
                      width: double.infinity,
                      icon: Icons.lock_rounded,
                      variant: canAfford
                          ? AppButtonVariant.primary
                          : AppButtonVariant.ghost,
                      onPressed: _paying || !canAfford ? null : _createSession,
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                  'Secured by Razorpay · escrow locked on Stellar testnet.',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    setState(() => _paying = true);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not logged in');

      final api = ref.read(apiServiceProvider);

      // 1. Create session intent (status: created)
      final session = await api.createIntent(
        riderId: user.id,
        hostId: widget.outlet.hostName, // TODO: map to actual hostId
        outletId: widget.outlet.id,
        depositCredits: _depositAmount,
        idempotencyKey:
            'intent_${user.id}_${widget.outlet.id}_${DateTime.now().millisecondsSinceEpoch}',
      );

      // 2. Start session (lock deposit + hardware ON)
      final started = await api.startSession(
        sessionId: session.id,
        idempotencyKey: 'start_${session.id}',
      );

      if (!mounted) return;
      setState(() => _paying = false);
      context.pushReplacement('/charging', extra: started);
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed: $e'), backgroundColor: AppColors.danger),
      );
    }
  }
}
