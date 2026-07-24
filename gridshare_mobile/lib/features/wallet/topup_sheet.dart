import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../data/providers.dart';
import '../../data/models/models.dart';

// ── Payment rail toggle ────────────────────────────────────────────────────

enum _Rail { upi, usdc }

// ── Top-up sheet ──────────────────────────────────────────────────────────

/// Top-up sheet — UPI (Razorpay) or USDC (Stellar SEP-0007) toggle.
/// Design system: GlassCard, AppButton, AppColors navy/cyan, smooth motion.
class TopUpSheet extends ConsumerStatefulWidget {
  final String userId;
  const TopUpSheet({super.key, required this.userId});

  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<TopUpSheet>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  _Rail _rail = _Rail.upi;
  int _amount = 100;
  bool _loading = false;

  // UPI
  final List<int> _presets = [50, 100, 200, 500, 1000];

  // USDC: FX + intent
  double? _usdInrRate = 96.50;
  bool _fxLoading = false;
  UsdcIntent? _intent;
  UsdcIntentStatus? _intentStatus;
  bool _isVerifying = false;
  Timer? _pollTimer;

  // Animation controller for rail-switch
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fetchFxRate();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── FX rate ─────────────────────────────────────────────────────────────
  Future<void> _fetchFxRate() async {
    if (_fxLoading) return;
    setState(() => _fxLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final fx = await api.getFxRate();
      if (mounted && fx.rate > 0) {
        setState(() {
          _usdInrRate = fx.rate;
          _fxLoading = false;
        });
        return;
      }
    } catch (_) {}

    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final rate = (body['rates']?['INR'] as num?)?.toDouble();
        if (mounted && rate != null && rate > 0) {
          setState(() {
            _usdInrRate = rate;
            _fxLoading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _usdInrRate ??= 96.50;
        _fxLoading = false;
      });
    }
  }

  // ── Instamojo UPI top-up ──────────────────────────────────────────────────
  Future<void> _topUpUpi() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final order = await api.createInstamojoOrder(
        amountCredits: _amount,
        userId: widget.userId,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      // Open Instamojo hosted payment page in a full-screen WebView screen
      final result = await Navigator.push<_InstamojoResult>(
        context,
        MaterialPageRoute(
          builder: (_) => _InstamojoWebViewScreen(paymentUrl: order.paymentUrl),
        ),
      );

      if (result != null && result.paymentId != null) {
        setState(() => _loading = true);
        // Verify payment on backend & mint credits
        await api.verifyInstamojoPayment(
          paymentRequestId: result.requestId ?? order.requestId,
          paymentId: result.paymentId!,
          userId: widget.userId,
          amountCredits: _amount,
        );

        final balance = await api.getBalance(userId: widget.userId);
        if (!mounted) return;
        ref.read(currentUserProvider.notifier).state =
            ref.read(currentUserProvider)!.copyWith(
                  walletBalanceCredits: balance.balanceCredits,
                );
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '₹$_amount credits added via Instamojo UPI! Balance: ${balance.balanceCredits}'),
          backgroundColor: AppColors.accent,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Instamojo UPI error: $e'),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── USDC top-up ─────────────────────────────────────────────────────────
  Future<void> _createUsdcIntent() async {
    setState(() => _loading = true);
    _pollTimer?.cancel();
    _intentStatus = null;
    try {
      final api = ref.read(apiServiceProvider);
      final intent = await api.createUsdcIntent(
        userId: widget.userId,
        amountCredits: _amount,
        assetCode: 'XLM',
      );
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _usdInrRate = intent.lockedRate;
      });
      _startPolling(intent.memo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to create USDC intent: $e'),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPolling(String memo) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final api = ref.read(apiServiceProvider);
        final status = await api.pollUsdcIntent(memo: memo);
        if (!mounted) return;
        setState(() => _intentStatus = status);
        if (status.isConfirmed || status.isExpired) {
          _pollTimer?.cancel();
          if (status.isConfirmed) {
            final balance = await api.getBalance(userId: widget.userId);
            if (!mounted) return;
            ref.read(currentUserProvider.notifier).state =
                ref.read(currentUserProvider)!.copyWith(
                      walletBalanceCredits: balance.balanceCredits,
                    );
          }
        }
      } catch (_) {}
    });
  }

  void _resetUsdc() {
    _pollTimer?.cancel();
    setState(() {
      _intent = null;
      _intentStatus = null;
      _isVerifying = false;
    });
  }

  Future<void> _verifyUsdcPayment() async {
    if (_intent == null || _isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final api = ref.read(apiServiceProvider);
      final status = await api.verifyUsdcIntent(memo: _intent!.memo);
      if (!mounted) return;
      setState(() => _intentStatus = status);
      if (status.isConfirmed) {
        _pollTimer?.cancel();
        try {
          final balance = await api.getBalance(userId: widget.userId);
          if (mounted) {
            ref.read(currentUserProvider.notifier).state =
                ref.read(currentUserProvider)!.copyWith(
                      walletBalanceCredits: balance.balanceCredits,
                    );
          }
        } catch (_) {}
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✓ Payment verified! ${_intent!.amountCredits} credits added to your wallet.'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  status.status == 'pending'
                      ? 'No matching payment found yet on Stellar. Please try again after sending.'
                      : 'Status: ${status.status}'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verify error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied!'),
      duration: const Duration(seconds: 2),
      backgroundColor: AppColors.surfaceHigh,
    ));
  }

  // ── Rail switch ──────────────────────────────────────────────────────────
  void _switchRail(_Rail rail) {
    if (_rail == rail) return;
    _resetUsdc();
    setState(() => _rail = rail);
    if (rail == _Rail.usdc) {
      _animCtrl.forward();
      if (_usdInrRate == null) _fetchFxRate();
    } else {
      _animCtrl.reverse();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Rail toggle ──────────────────────────────────────────
              _RailToggle(
                selected: _rail,
                onChanged: _loading ? null : _switchRail,
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Rail body ─────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                child: _rail == _Rail.upi
                    ? _UpiBody(
                        key: const ValueKey('upi'),
                        amount: _amount,
                        presets: _presets,
                        loading: _loading,
                        onAmountChanged: (v) => setState(() => _amount = v),
                        onTopUp: _topUpUpi,
                      )
                    : _UsdcBody(
                        key: const ValueKey('usdc'),
                        amount: _amount,
                        presets: _presets,
                        usdInrRate: _usdInrRate,
                        fxLoading: _fxLoading,
                        intent: _intent,
                        intentStatus: _intentStatus,
                        loading: _loading,
                        isVerifying: _isVerifying,
                        onAmountChanged: (v) => setState(() => _amount = v),
                        onConfirm: _createUsdcIntent,
                        onReset: _resetUsdc,
                        onVerify: _verifyUsdcPayment,
                        onCopy: _copyToClipboard,
                        onRefreshFx: _fetchFxRate,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rail Toggle Widget ───────────────────────────────────────────────────

class _RailToggle extends StatelessWidget {
  final _Rail selected;
  final ValueChanged<_Rail>? onChanged;

  const _RailToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
            label: 'UPI',
            icon: Icons.account_balance_wallet_rounded,
            active: selected == _Rail.upi,
            color: AppColors.accent,
            onTap: onChanged != null ? () => onChanged!(_Rail.upi) : null,
          ),
          const SizedBox(width: 4),
          _Pill(
            label: 'XLM',
            icon: Icons.currency_bitcoin,
            active: selected == _Rail.usdc,
            color: const Color(0xFF9B59B6), // stellar purple
            onTap: onChanged != null ? () => onChanged!(_Rail.usdc) : null,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  const _Pill({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
        border: Border.all(
          color: active ? color.withOpacity(0.4) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16, color: active ? color : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? color : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Custom Amount Input Widget ─────────────────────────────────────────────

class _CustomAmountInput extends StatefulWidget {
  final int amount;
  final ValueChanged<int> onAmountChanged;
  final bool loading;
  final Color activeColor;

  const _CustomAmountInput({
    required this.amount,
    required this.onAmountChanged,
    required this.loading,
    required this.activeColor,
  });

  @override
  State<_CustomAmountInput> createState() => _CustomAmountInputState();
}

class _CustomAmountInputState extends State<_CustomAmountInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.amount.toString());
  }

  @override
  void didUpdateWidget(_CustomAmountInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount &&
        _controller.text != widget.amount.toString()) {
      _controller.text = widget.amount.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: widget.activeColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, color: widget.activeColor, size: 22),
          const SizedBox(width: 10),
          const Text('Custom amount: ₹',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              enabled: !widget.loading,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.activeColor),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'Enter amount > 0',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                final parsed = int.tryParse(val);
                if (parsed != null && parsed > 0) {
                  widget.onAmountChanged(parsed);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom USD Amount Input Widget ──────────────────────────────────────────

class _CustomUsdAmountInput extends StatefulWidget {
  final int creditAmount;
  final double? usdInrRate;
  final ValueChanged<int> onCreditAmountChanged;
  final bool loading;
  final Color activeColor;

  const _CustomUsdAmountInput({
    required this.creditAmount,
    required this.usdInrRate,
    required this.onCreditAmountChanged,
    required this.loading,
    required this.activeColor,
  });

  @override
  State<_CustomUsdAmountInput> createState() => _CustomUsdAmountInputState();
}

class _CustomUsdAmountInputState extends State<_CustomUsdAmountInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initialUsd = widget.usdInrRate != null && widget.usdInrRate! > 0
        ? (widget.creditAmount / widget.usdInrRate!).toStringAsFixed(2)
        : '5.00';
    _controller = TextEditingController(text: initialUsd);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: widget.activeColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.monetization_on_outlined,
              color: widget.activeColor, size: 22),
          const SizedBox(width: 10),
          const Text('Custom amount: \$',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !widget.loading,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.activeColor),
              decoration: const InputDecoration(
                hintText: 'e.g. 50 (USD)',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (val) {
                final usd = double.tryParse(val);
                if (usd != null && usd > 0) {
                  final rate = widget.usdInrRate ?? 95.0;
                  final credits = (usd * rate).round();
                  widget.onCreditAmountChanged(credits);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── UPI Body ─────────────────────────────────────────────────────────────

class _UpiBody extends StatelessWidget {
  final int amount;
  final List<int> presets;
  final bool loading;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onTopUp;

  const _UpiBody({
    super.key,
    required this.amount,
    required this.presets,
    required this.loading,
    required this.onAmountChanged,
    required this.onTopUp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlide(
          delay: const Duration(milliseconds: 60),
          child: GlassCard(
            glow: true,
            glowColor: AppColors.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GradientText('Add Credits',
                    style: AppTextStyles.heading, shimmer: false),
                const SizedBox(height: 4),
                const Text('1 credit = ₹1', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GradientText(amount.toString(),
                        style: AppTextStyles.display, shimmer: false),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('credits',
                          style: TextStyle(
                              fontSize: 20,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('≈ ₹$amount', style: AppTextStyles.caption),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text('Choose amount', style: AppTextStyles.label),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          children: presets
              .map((p) => ChoiceChip(
                    label: Text('₹$p'),
                    selected: amount == p,
                    onSelected: loading ? null : (_) => onAmountChanged(p),
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceHigh,
                    labelStyle: TextStyle(
                      color: amount == p
                          ? AppColors.background
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                  ))
              .toList(),
        ),
        _CustomAmountInput(
          amount: amount,
          onAmountChanged: onAmountChanged,
          loading: loading,
          activeColor: AppColors.accent,
        ),
        const SizedBox(height: AppSpacing.xxl),
        FadeSlide(
          delay: const Duration(milliseconds: 160),
          child: AppButton(
            label: loading ? 'Creating order…' : 'Pay with UPI',
            loading: loading,
            width: double.infinity,
            icon: Icons.account_balance_wallet_rounded,
            onPressed: (loading || amount <= 0) ? null : onTopUp,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Secured by Instamojo · credits minted on Stellar testnet.',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── USDC Body ─────────────────────────────────────────────────────────────

class _UsdcBody extends StatelessWidget {
  final int amount;
  final List<int> presets;
  final double? usdInrRate;
  final bool fxLoading;
  final UsdcIntent? intent;
  final UsdcIntentStatus? intentStatus;
  final bool loading;
  final bool isVerifying;
  final ValueChanged<int> onAmountChanged;
  final VoidCallback onConfirm;
  final VoidCallback onReset;
  final VoidCallback onVerify;
  final void Function(String text, String label) onCopy;
  final VoidCallback onRefreshFx;

  const _UsdcBody({
    super.key,
    required this.amount,
    required this.presets,
    required this.usdInrRate,
    required this.fxLoading,
    required this.intent,
    required this.intentStatus,
    required this.loading,
    required this.isVerifying,
    required this.onAmountChanged,
    required this.onConfirm,
    required this.onReset,
    required this.onVerify,
    required this.onCopy,
    required this.onRefreshFx,
  });

  @override
  Widget build(BuildContext context) {
    // If we have an intent, show the deposit QR view.
    if (intent != null) {
      return _UsdcDepositView(
        intent: intent!,
        status: intentStatus,
        isVerifying: isVerifying,
        onReset: onReset,
        onVerify: onVerify,
        onCopy: onCopy,
      );
    }

    // Otherwise show the amount picker + quote.
    final expectedUsdc =
        usdInrRate != null ? (amount / usdInrRate!).toStringAsFixed(4) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live FX rate banner with vibrant purple/indigo gradient
        FadeSlide(
          delay: const Duration(milliseconds: 40),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8E44AD), Color(0xFF6C5CE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8E44AD).withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: const Icon(Icons.currency_exchange_rounded,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Exchange Rate',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70),
                      ),
                      const SizedBox(height: 2),
                      fxLoading
                          ? const SizedBox(
                              height: 18,
                              width: 100,
                              child: LinearProgressIndicator(
                                backgroundColor: Colors.white24,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              usdInrRate != null
                                  ? '1 USD = ₹${usdInrRate!.toStringAsFixed(2)}'
                                  : 'Rate unavailable',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      size: 20, color: Colors.white),
                  onPressed: fxLoading ? null : onRefreshFx,
                  tooltip: 'Refresh rate',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Amount picker
        FadeSlide(
          delay: const Duration(milliseconds: 80),
          child: GlassCard(
            glow: true,
            glowColor: const Color(0xFF9B59B6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Credits via Stellar XLM',
                    style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount.toString(),
                      style: AppTextStyles.display
                          .copyWith(color: const Color(0xFF9B59B6)),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('credits',
                          style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFF9B59B6),
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                if (expectedUsdc != null)
                  Text(
                    'You send: $expectedUsdc XLM',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        const Text('Choose amount (USD quote / XLM testnet)',
            style: AppTextStyles.label),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          children: [5, 10, 25, 50, 100].map((usdVal) {
            final rate = usdInrRate ?? 95.0;
            final creditVal = (usdVal * rate).round();
            final isSelected = (amount - creditVal).abs() < 5;
            return ChoiceChip(
              label: Text('\$$usdVal'),
              selected: isSelected,
              onSelected: loading ? null : (_) => onAmountChanged(creditVal),
              selectedColor: const Color(0xFF9B59B6),
              backgroundColor: AppColors.surfaceHigh,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            );
          }).toList(),
        ),
        _CustomUsdAmountInput(
          creditAmount: amount,
          usdInrRate: usdInrRate,
          onCreditAmountChanged: onAmountChanged,
          loading: loading,
          activeColor: const Color(0xFF9B59B6),
        ),

        const SizedBox(height: AppSpacing.xxl),

        FadeSlide(
          delay: const Duration(milliseconds: 160),
          child: AppButton(
            label: loading ? 'Generating Payment Quote…' : 'Pay with XLM',
            loading: loading,
            width: double.infinity,
            icon: Icons.account_balance_wallet_rounded,
            onPressed: loading ? null : onConfirm,
          ),
        ),

        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Testnet XLM · Powered by Stellar',
          style: AppTextStyles.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── USDC Deposit View (after intent created) ──────────────────────────────

class _UsdcDepositView extends StatelessWidget {
  final UsdcIntent intent;
  final UsdcIntentStatus? status;
  final bool isVerifying;
  final VoidCallback onReset;
  final VoidCallback onVerify;
  final void Function(String text, String label) onCopy;

  const _UsdcDepositView({
    required this.intent,
    required this.status,
    required this.isVerifying,
    required this.onReset,
    required this.onVerify,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isConfirmed = status?.isConfirmed ?? false;
    final isExpired = status?.isExpired ?? false;
    final isPending = !isConfirmed && !isExpired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status banner
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm, horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: isConfirmed
                ? AppColors.success.withOpacity(0.12)
                : isExpired
                    ? AppColors.danger.withOpacity(0.12)
                    : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppSpacing.rMd),
            border: Border.all(
              color: isConfirmed
                  ? AppColors.success.withOpacity(0.4)
                  : isExpired
                      ? AppColors.danger.withOpacity(0.4)
                      : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isConfirmed
                    ? Icons.check_circle_rounded
                    : isExpired
                        ? Icons.cancel_rounded
                        : Icons.access_time_rounded,
                color: isConfirmed
                    ? AppColors.success
                    : isExpired
                        ? AppColors.danger
                        : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isConfirmed
                    ? '✓ Payment confirmed! Credits minted.'
                    : isExpired
                        ? 'Intent expired. Please create a new one.'
                        : 'Waiting for ${intent.assetCode} payment…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isConfirmed
                      ? AppColors.success
                      : isExpired
                          ? AppColors.danger
                          : AppColors.textSecondary,
                ),
              ),
              if (isPending) ...[
                const Spacer(),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // QR Code
        FadeSlide(
          delay: const Duration(milliseconds: 60),
          child: GlassCard(
            glow: true,
            glowColor: const Color(0xFF9B59B6),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Text('Scan with Stellar Wallet (Stellar Network)',
                    style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    ),
                    child: QrImageView(
                      data: intent.depositAddress,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Send ${intent.expectedUsdc.toStringAsFixed(4)} ${intent.assetCode}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '= ${intent.amountCredits} credits',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Deposit address
        FadeSlide(
          delay: const Duration(milliseconds: 120),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stellar Network Address',
                    style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        intent.depositAddress,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: AppColors.accent),
                      onPressed: () =>
                          onCopy(intent.depositAddress, 'Stellar Address'),
                      tooltip: 'Copy address',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Memo
        FadeSlide(
          delay: const Duration(milliseconds: 160),
          child: GlassCard(
            glow: true,
            glowColor: AppColors.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    const Text('IMPORTANT: Include this Memo',
                        style: AppTextStyles.label),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        intent.memo,
                        style: const TextStyle(
                          fontSize: 15,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: AppColors.warning),
                      onPressed: () => onCopy(intent.memo, 'Memo'),
                      tooltip: 'Copy memo',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Without the memo your payment cannot be matched.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        if (isPending)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppButton(
              label: isVerifying ? 'Verifying on Stellar...' : 'I Have Paid / Check Status',
              width: double.infinity,
              icon: isVerifying ? null : Icons.sync_rounded,
              onPressed: isVerifying ? null : onVerify,
            ),
          ),

        if (isExpired || isConfirmed)
          AppButton(
            label: isConfirmed ? 'Done' : 'Start Over',
            width: double.infinity,
            icon: isConfirmed ? Icons.check_rounded : Icons.refresh_rounded,
            onPressed: () {
              if (isConfirmed) {
                Navigator.pop(context, true);
              } else {
                onReset();
              }
            },
          ),
      ],
    );
  }

  void _showWalletConnectModal(BuildContext context, UsdcIntent intent) {
    const projectId = '3f139c3090412322bc70d9d894dadb38';
    final wcUri =
        'wc:gridshare-usdc-pay-${intent.memo}?projectId=$projectId&amount=${intent.expectedUsdc}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF3B99FC).withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.account_balance_wallet,
                      color: Color(0xFF3B99FC), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WalletConnectPay SDK',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      Text('Project ID: 3f139c309...b38',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text('Amount: ${intent.expectedUsdc.toStringAsFixed(4)} USDC',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Memo: ${intent.memo}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppColors.accent)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wcUri));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          '✓ WalletConnect URI copied! Connect with Trust, LOBSTR or Web3 wallet.'),
                      backgroundColor: Color(0xFF3B99FC)),
                );
              },
              icon:
                  const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
              label: const Text('Copy WalletConnect Pay URI',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B99FC),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _InstamojoResult {
  final String? paymentId;
  final String? requestId;
  final String? status;
  _InstamojoResult({this.paymentId, this.requestId, this.status});
}

class _InstamojoWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  const _InstamojoWebViewScreen({required this.paymentUrl});

  @override
  State<_InstamojoWebViewScreen> createState() =>
      _InstamojoWebViewScreenState();
}

class _InstamojoWebViewScreenState extends State<_InstamojoWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            final url = Uri.parse(request.url);
            // Check if Instamojo redirected back to our redirect URL
            if (url.path.contains('/wallet/topup/instamojo/redirect') ||
                url.queryParameters.containsKey('payment_id')) {
              final paymentId = url.queryParameters['payment_id'];
              final requestId = url.queryParameters['payment_request_id'];
              final status = url.queryParameters['payment_status'];
              Navigator.pop(
                context,
                _InstamojoResult(
                  paymentId: paymentId,
                  requestId: requestId,
                  status: status,
                ),
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Instamojo UPI Payment',
            style: TextStyle(fontSize: 16, color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
        ],
      ),
    );
  }
}
