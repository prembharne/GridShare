import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../core/utils/currency.dart';
import '../../data/providers.dart';
import '../../data/models/models.dart';
import 'listing_settings_screen.dart';
import 'iot_config_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool isHost;
  final ValueChanged<bool> onRoleChanged;

  const ProfileScreen({
    super.key,
    required this.isHost,
    required this.onRoleChanged,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Role state now owned by HomeScreen; mirrored here for local UI rebuild.
  bool get _isHost => widget.isHost;
  double _mockEarnings = 840.0;
  bool _isKycVerified = false;

  // Role-specific theme helpers
  Color get _primaryAccent => _isHost ? AppColors.hostAccent : AppColors.accent;
  Color get _softAccent    => _isHost ? AppColors.hostAccentSoft : AppColors.accentSoft;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text('Profile', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                // ── User Avatar Row ────────────────────────────────────────
                Row(
                  children: [
                    OrbitingRing(
                      size: 64,
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.surfaceHigh,
                        child: Text(
                          user?.name.isNotEmpty == true ? user!.name[0] : '?',
                          style: TextStyle(color: _primaryAccent, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GradientText(user?.name ?? 'Rider',
                              style: AppTextStyles.heading, shimmer: false),
                          Text(user?.phone ?? '+91 ———', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, curve: Curves.easeOutQuart),
                const SizedBox(height: AppSpacing.lg),

                // ── Role Switcher Toggle ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onRoleChanged(false),
                          child: AnimatedContainer(
                            duration: 250.ms,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: !_isHost ? AppColors.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppSpacing.rSm),
                              boxShadow: !_isHost ? [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                )
                              ] : [],
                            ),
                            child: Center(
                              child: Text(
                                '🚗  Rider',
                                style: TextStyle(
                                  color: !_isHost ? AppColors.background : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onRoleChanged(true),
                          child: AnimatedContainer(
                            duration: 250.ms,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _isHost ? AppColors.hostAccent : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppSpacing.rSm),
                              boxShadow: _isHost ? [
                                BoxShadow(
                                  color: AppColors.hostAccent.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                )
                              ] : [],
                            ),
                            child: Center(
                              child: Text(
                                '🏡  Host',
                                style: TextStyle(
                                  color: _isHost ? AppColors.background : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 50.ms, duration: 600.ms),
                const SizedBox(height: AppSpacing.lg),

                // ── Wallet / Earnings Card ──────────────────────────────────
                AnimatedSwitcher(
                  duration: 350.ms,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child)),
                  child: GlassCard(
                    key: ValueKey(_isHost),
                    glow: true,
                    glowColor: _primaryAccent,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isHost ? 'Host earnings' : 'Wallet balance',
                          style: AppTextStyles.label,
                        ),
                        Text(
                          _isHost
                              ? '${_mockEarnings.toInt()} credits'
                              : Compliance.rupees(user?.walletBalanceCredits?.toDouble() ?? 0),
                          style: AppTextStyles.title.copyWith(
                            color: _primaryAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms, duration: 600.ms),

                // ── RIDER ONLY: Active Charging Status Card ─────────────────
                if (!_isHost) ...[
                  const SizedBox(height: AppSpacing.sm),
                  GlassCard(
                    glow: true,
                    glowColor: AppColors.accent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(AppSpacing.rSm),
                              ),
                              child: const Icon(Icons.electric_bolt_rounded,
                                  color: AppColors.accent, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Active Charging',
                                    style: AppTextStyles.label.copyWith(color: AppColors.accent)),
                                Text('No active session',
                                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.textMuted.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Idle',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // Progress Bar
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: 0.65,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: AppColors.accentGlow,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accent.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('⚡ Charging: 65%',
                            style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpacing.md),
                        // Metrics Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _MetricChip(label: 'Rate', value: '3.3 kW'),
                            _MetricDivider(),
                            _MetricChip(label: 'Remaining', value: '45 mins'),
                            _MetricDivider(),
                            _MetricChip(label: 'Cost', value: '42 credits'),
                          ],
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.1, curve: Curves.easeOut),
                ],

                // ── HOST ONLY: Badges ───────────────────────
                if (_isHost) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                        decoration: BoxDecoration(
                          color: AppColors.hostAccentSoft,
                          borderRadius: BorderRadius.circular(AppSpacing.rSm),
                          border: Border.all(color: AppColors.hostAccent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded, color: AppColors.hostAccent, size: 14),
                            const SizedBox(width: AppSpacing.xs),
                            const Text(
                              '⚡ Dedicated EV Connection: Verified',
                              style: TextStyle(
                                color: AppColors.hostAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppSpacing.rSm),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending_actions_rounded, color: AppColors.warning, size: 14),
                            const SizedBox(width: AppSpacing.xs),
                            const Text(
                              '👤 Identity Verification (KYC): Pending',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 150.ms),
                ],

                const SizedBox(height: AppSpacing.md),

                // ── Monthly Review ─────────────────────────────────────────
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('MONTHLY REVIEW', style: AppTextStyles.label),
                ),
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatBlock(
                        label: _isHost ? 'Sessions hosted' : 'Bookings',
                        value: '0',
                        icon: _isHost ? Icons.ev_station_rounded : Icons.calendar_today_rounded,
                        color: _primaryAccent,
                      ),
                      _StatBlock(
                        label: _isHost ? 'Earned' : 'Spent',
                        value: '0 credits',
                        icon: _isHost ? Icons.payments_rounded : Icons.account_balance_wallet_rounded,
                        color: _primaryAccent,
                      ),
                      _StatBlock(
                        label: _isHost ? 'Energy Shared' : 'Energy',
                        value: '0.0 kWh',
                        icon: Icons.bolt_rounded,
                        color: _primaryAccent,
                      ),
                    ].animate(interval: 80.ms).fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8)),
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 600.ms).scale(
                    begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack),
                const SizedBox(height: AppSpacing.md),

                // ── Role-Specific Menu ─────────────────────────────────────
                AnimatedSwitcher(
                  duration: 400.ms,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _isHost ? _buildHostMenu(context) : _buildRiderMenu(context, user),
                ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.1),

                const SizedBox(height: AppSpacing.xxl),
                TextButton(
                  onPressed: () {
                    ref.read(currentUserProvider.notifier).state = null;
                    context.go('/auth');
                  },
                  child: const Text('Log out',
                      style: TextStyle(color: AppColors.danger, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── RIDER MENU ─────────────────────────────────────────────────────────────
  Widget _buildRiderMenu(BuildContext context, User? user) {
    return GlassCard(
      key: const ValueKey('rider_menu'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _RowTile(
            icon: Icons.receipt_long_rounded,
            title: 'My sessions',
            subtitle: 'Service fee receipts',
            color: AppColors.accent,
            onTap: () {},
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.directions_car_rounded,
            title: 'My Vehicles',
            subtitle: 'Manage your EV models & plug types',
            color: AppColors.accent,
            onTap: () => _showVehiclesSheet(context),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.add_card_rounded,
            title: 'Top up',
            subtitle: 'Add money to your wallet',
            color: AppColors.accent,
            onTap: () {
              if (user != null) {
                context.push('/wallet/topup', extra: {'userId': user.id});
              }
            },
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.card_giftcard_rounded,
            title: 'Refer & earn',
            subtitle: 'Invite friends, earn credits',
            color: AppColors.accent,
            onTap: () => _showReferralDialog(context),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.shield_rounded,
            title: 'How GridShare stays legal',
            subtitle: 'Service, not electricity resale',
            color: AppColors.accent,
            onTap: () {},
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.help_outline_rounded,
            title: 'Help & safety',
            subtitle: '24/7 Support & Safety',
            color: AppColors.accent,
            onTap: () {},
          ),
        ].animate(interval: 40.ms).fadeIn(duration: 300.ms).slideX(begin: 0.05, curve: Curves.easeOutQuart),
      ),
    );
  }

  // ── HOST MENU ──────────────────────────────────────────────────────────────
  Widget _buildHostMenu(BuildContext context) {
    return GlassCard(
      key: const ValueKey('host_menu'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _RowTile(
            icon: Icons.power_rounded,
            title: 'My listings',
            subtitle: 'Manage plug points',
            color: AppColors.hostAccent,
            onTap: () => Navigator.push(context, _slide(const ListingSettingsScreen())),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.electrical_services_rounded,
            title: 'Configure IoT Smart Plug',
            subtitle: 'Pair, sync, or reboot your GridShare IoT hardware',
            color: AppColors.hostAccent,
            onTap: () => Navigator.push(context, _slide(const IoTConfigScreen())),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.price_check_rounded,
            title: 'Withdraw earnings',
            subtitle: 'Payout to bank account',
            color: AppColors.hostAccent,
            onTap: () => _showWithdrawModal(context),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.download_rounded,
            title: 'Tax & DISCOM Statement',
            subtitle: 'Export monthly kWh and earnings history',
            color: AppColors.hostAccent,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tax & DISCOM statement download started…'),
                  backgroundColor: AppColors.hostAccent,
                ),
              );
            },
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.card_giftcard_rounded,
            title: 'Refer & earn',
            subtitle: 'Invite hosts, earn credits',
            color: AppColors.hostAccent,
            onTap: () => _showReferralDialog(context),
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.gavel_rounded,
            title: 'Hosting regulations',
            subtitle: 'Zoning & safety guidelines',
            color: AppColors.hostAccent,
            onTap: () {},
          ),
          const Divider(height: 1, color: AppColors.border, indent: 56),
          _RowTile(
            icon: Icons.help_outline_rounded,
            title: 'Help & safety',
            subtitle: '24/7 Support & Safety',
            color: AppColors.hostAccent,
            onTap: () {},
          ),
        ].animate(interval: 40.ms).fadeIn(duration: 300.ms).slideX(begin: 0.05, curve: Curves.easeOutQuart),
      ),
    );
  }

  // ── Navigation Helper ──────────────────────────────────────────────────────
  Route _slide(Widget page) => PageRouteBuilder(
        pageBuilder: (_, anim, __) => page,
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutQuart)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
      );

  // ── My Vehicles Bottom Sheet ───────────────────────────────────────────────
  void _showVehiclesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car_rounded, color: AppColors.accent, size: 22),
                const SizedBox(width: AppSpacing.sm),
                const Text('My Vehicles', style: AppTextStyles.heading),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Plug type selector
            Text('SELECT PLUG TYPE', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: ['5-Amp', '15-Amp', 'Type-2 AC', 'CCS2', 'CHAdeMO']
                  .map((plug) => _PlugChip(label: plug))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('MY EVs', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            _VehicleItem(name: 'Ather 450X', plug: '5-Amp'),
            _VehicleItem(name: 'Tata Nexon EV', plug: 'Type-2 AC'),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rMd),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Vehicle'),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  // ── Referral Dialog ────────────────────────────────────────────────────────
  void _showReferralDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          glow: true,
          glowColor: _primaryAccent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_giftcard_rounded, color: _primaryAccent, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text('Refer & Earn', style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Share GridShare with your friends! When they sign up and complete their first charge, you both get 100 credits.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('GRID500',
                        style: TextStyle(
                          color: _primaryAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        )),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: AppColors.textSecondary),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Referral code copied!'),
                            backgroundColor: AppColors.accent,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Withdraw / Settlement Modal ────────────────────────────────────────────
  String _getUpcomingMonday() {
    DateTime now = DateTime.now();
    int days = (DateTime.monday - now.weekday + 7) % 7;
    if (days == 0) days = 7;
    DateTime monday = now.add(Duration(days: days));
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Monday, ${monday.day} ${months[monday.month - 1]} ${monday.year}';
  }

  void _showWithdrawModal(BuildContext context) {
    if (!_isKycVerified) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: GlassCard(
            glow: true,
            glowColor: AppColors.warning,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 48),
                const SizedBox(height: AppSpacing.md),
                const Text('KYC Verification Required', style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Please complete your identity verification to enable weekly bank payouts to your UPI ID.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _isKycVerified = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Identity verification submitted.'),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rMd),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Complete KYC', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          glow: true,
          glowColor: AppColors.hostAccent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_rounded, color: AppColors.hostAccent, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text('Automated Settlement', style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your earned credits are automatically settled to your registered bank account or UPI ID every Monday.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: AppColors.hostAccent, size: 16),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Next Settlement:\n${_getUpcomingMonday()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.hostAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _RowTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  const _RowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.title),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatBlock({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTextStyles.title.copyWith(fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            )),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.border);
  }
}

class _PlugChip extends StatefulWidget {
  final String label;
  const _PlugChip({required this.label});

  @override
  State<_PlugChip> createState() => _PlugChipState();
}

class _PlugChipState extends State<_PlugChip> {
  bool _selected = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _selected = !_selected),
      child: AnimatedContainer(
        duration: 250.ms,
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _selected ? AppColors.accentSoft : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _selected ? AppColors.accent : AppColors.border,
            width: _selected ? 1.5 : 1,
          ),
        ),
        child: Text(widget.label,
            style: TextStyle(
              color: _selected ? AppColors.accent : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: _selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }
}

class _VehicleItem extends StatelessWidget {
  final String name;
  final String plug;
  const _VehicleItem({required this.name, required this.plug});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.rMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.electric_car_rounded, color: AppColors.accent, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.title),
                Text('Plug: $plug', style: AppTextStyles.caption),
              ],
            ),
          ),
          const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
