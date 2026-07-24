// Copyright 2024 GridShare. All rights reserved.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/currency.dart';
import '../../data/providers.dart';
import '../../data/models/models.dart';
import '../../data/services/real_services.dart';
import '../../core/widgets/glass_card.dart';


import 'listing_settings_screen.dart';
import 'iot_config_screen.dart';
import 'kyc_screen.dart';

/// Redesigned Profile Screen with clean light/pastel theme, slate typography,
/// and a custom sliding role switch toggle.
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
  bool get _isHost => widget.isHost;
  bool _isKycVerified = false;

  // Host earnings source ledger (UPI + USDC buckets)
  HostSourceLedger? _sourceLedger;
  bool _earningsLoading = false;

  Color get _primaryAccent => _isHost ? AppColors.hostAccent : AppColors.accent;

  @override
  void initState() {
    super.initState();
    if (widget.isHost) _fetchSourceLedger();
    // Refresh wallet balance from backend on every screen open
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBalance());
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHost && !oldWidget.isHost) _fetchSourceLedger();
  }

  Future<void> _fetchSourceLedger() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _earningsLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final ledger = await api.getSourceLedger(userId: user.id);
      if (mounted) setState(() => _sourceLedger = ledger);
    } catch (_) {
      // Non-fatal — show zeros
    } finally {
      if (mounted) setState(() => _earningsLoading = false);
    }
  }

  Future<void> _refreshBalance() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final api = ref.read(apiServiceProvider);
      final bal = await api.getBalance(userId: user.id);
      if (mounted && bal.balanceCredits != user.walletBalanceCredits) {
        ref.read(currentUserProvider.notifier).state =
            user.copyWith(walletBalanceCredits: bal.balanceCredits);
      }
    } catch (_) {
      // Non-fatal
    }
  }

  void _showEditProfileDialog(BuildContext context, User? currentUser) {

    final nameCtrl = TextEditingController(text: currentUser?.name ?? '');
    final phoneCtrl = TextEditingController(text: currentUser?.phone ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Avatar preview
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: AppColors.accent.withOpacity(0.15),
                        child: Text(
                          nameCtrl.text.isNotEmpty ? nameCtrl.text[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Full Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter your name',
                    prefixIcon: const Icon(Icons.person_outline, size: 20, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Mobile Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+91 9876543210',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    final newName = nameCtrl.text.trim();
                    final newPhone = phoneCtrl.text.trim();
                    if (newName.isEmpty) return;

                    final updated = (currentUser ?? const User(id: 'user_1', name: 'Rider', phone: '', walletBalanceCredits: 0)).copyWith(
                      name: newName,
                      phone: newPhone,
                    );

                    ref.read(currentUserProvider.notifier).state = updated;
                    await SecureStorage().saveUserData(updated);

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✓ Profile updated successfully!'), backgroundColor: AppColors.accent),
                      );
                    }
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Colors.transparent, // Inherits the background gradient
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary, // Slate 900
          ),
        ),
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
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _primaryAccent.withOpacity(0.3), width: 2),
                      ),
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
                          Text(
                            user?.name ?? 'Rider',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            user?.phone ?? '+91 ———',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showEditProfileDialog(context, user),
                      icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
                      label: const Text('Edit Profile', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.accent, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, curve: Curves.easeOutQuart),
                const SizedBox(height: AppSpacing.lg),

                // ── Redesigned Sliding Switcher Toggle ──────────────────────
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.border, // Slate 200 (light gray)
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth / 2;
                      return Stack(
                        children: [
                          // Sliding capsule background
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            left: _isHost ? width : 0,
                            right: _isHost ? 0 : width,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _isHost ? AppColors.hostAccent : AppColors.accent, // Emerald / Indigo
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isHost ? AppColors.hostAccent : AppColors.accent).withOpacity(0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Text labels overlay
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => widget.onRoleChanged(false),
                                  behavior: HitTestBehavior.opaque,
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        color: !_isHost ? Colors.white : AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      child: const Text('🚗  Rider'),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => widget.onRoleChanged(true),
                                  behavior: HitTestBehavior.opaque,
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        color: _isHost ? Colors.white : AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      child: const Text('🏡  Host'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ).animate().fadeIn(delay: 50.ms, duration: 600.ms),
                const SizedBox(height: AppSpacing.lg),

                // ── Wallet / Earnings Card ──────────────────────────────────
                AnimatedSwitcher(
                  duration: 350.ms,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child)),
                  child: _isHost
                      ? _HostEarningsSection(
                          key: const ValueKey('host_earnings'),
                          sourceLedger: _sourceLedger,
                          loading: _earningsLoading,
                          onRefresh: _fetchSourceLedger,
                        )
                      : Container(
                          key: const ValueKey('rider_balance'),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Wallet balance',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                '${user?.walletBalanceCredits ?? 0} credits',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                ).animate().fadeIn(delay: 100.ms, duration: 600.ms),

                // ── RIDER ONLY: Active Charging Status Card ─────────────────
                // Removed until dynamic session state is implemented
                if (!_isHost) ...[
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
                            horizontal: AppSpacing.md, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.hostAccentSoft, // emerald glow fill
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.hostAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, color: AppColors.hostAccent, size: 14),
                            SizedBox(width: AppSpacing.xs),
                            Text(
                              '⚡ Dedicated EV Connection: Verified',
                              style: TextStyle(
                                color: AppColors.hostAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12), // amber glow fill
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pending_actions_rounded, color: AppColors.warning, size: 14),
                            SizedBox(width: AppSpacing.xs),
                            Text(
                              '👤 Identity Verification (KYC): Pending',
                              style: TextStyle(
                                color: AppColors.warning, // amber
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
                  child: Text(
                    'MONTHLY REVIEW',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
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
                    ],
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
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('Log out',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
    return Container(
      key: const ValueKey('rider_menu'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
    return Container(
      key: const ValueKey('host_menu'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                const Text(
                  'My Vehicles',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Plug type selector
            const Text(
              'SELECT PLUG TYPE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: ['5-Amp', '15-Amp', 'Type-2 AC', 'CCS2', 'CHAdeMO']
                  .map((plug) => _PlugChip(label: plug))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'MY EVs',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            const _VehicleItem(name: 'Ather 450X', plug: '5-Amp'),
            const _VehicleItem(name: 'Tata Nexon EV', plug: 'Type-2 AC'),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  foregroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Vehicle', style: TextStyle(fontWeight: FontWeight.bold)),
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
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_giftcard_rounded, color: _primaryAccent, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Refer & Earn',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Share GridShare with your friends! When they sign up and complete their first charge, you both get 100 credits.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'GRID500',
                      style: TextStyle(
                        color: _primaryAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: AppColors.textSecondary),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Referral code copied!'),
                            backgroundColor: _primaryAccent,
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
                child: const Text('Close', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Withdraw Modal ─────────────────────────────────────────────────────────
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
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 48),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'KYC Verification Required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Please complete your identity verification to enable weekly bank payouts to your UPI ID.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final success = await Navigator.push(context, _slide(const KycScreen()));
                      if (success == true) {
                        setState(() => _isKycVerified = true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: AppColors.background,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Complete KYC', style: TextStyle(fontWeight: FontWeight.bold)),
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
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_rounded, color: AppColors.hostAccent, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Automated Settlement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Your earned credits are automatically settled to your registered bank account or UPI ID every Monday.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.hostAccentSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hostAccent.withValues(alpha: 0.4)),
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Row Tile ─────────────────────────────────────────────────────────────────
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Stat Block ───────────────────────────────────────────────────────────────
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
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── Metric Chip ──────────────────────────────────────────────────────────────
class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── Metric Divider ───────────────────────────────────────────────────────────
class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.border);
  }
}

// ── Plug Chip ────────────────────────────────────────────────────────────────
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: _selected ? AppColors.accentSoft : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _selected ? AppColors.accent : AppColors.border,
            width: _selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: _selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Vehicle Item ─────────────────────────────────────────────────────────────
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
        borderRadius: BorderRadius.circular(16),
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
                Text(
                  name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  'Plug: $plug',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

// ── Host Earnings Section ─────────────────────────────────────────────────
// Shows two separate buckets: UPI earnings (cyan) and USDC earnings (stellar
// purple), sourced from GET /wallet/:userId/source-ledger.

class _HostEarningsSection extends StatelessWidget {
  final HostSourceLedger? sourceLedger;
  final bool loading;
  final VoidCallback onRefresh;

  const _HostEarningsSection({
    super.key,
    required this.sourceLedger,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final upi = sourceLedger?.upi ?? 0;
    final usdc = sourceLedger?.usdc ?? 0;
    final total = upi + usdc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Text(
              'Host Earnings',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.hostAccent),
              )
            else
              GestureDetector(
                onTap: onRefresh,
                child: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Total
        if (total > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.hostAccentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.rMd),
              border: Border.all(color: AppColors.hostAccent.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total earned',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$total credits',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.hostAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // UPI bucket
        _EarningsBucket(
          label: 'UPI (Razorpay)',
          icon: Icons.account_balance_wallet_rounded,
          color: AppColors.accent,
          credits: upi,
          total: total,
          loading: loading,
        ),
        const SizedBox(height: AppSpacing.sm),

        // USDC bucket
        _EarningsBucket(
          label: 'USDC (Stellar)',
          icon: Icons.currency_bitcoin,
          color: const Color(0xFF9B59B6),
          credits: usdc,
          total: total,
          loading: loading,
        ),

        if (!loading && total == 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.bolt_outlined, size: 32, color: AppColors.textMuted.withOpacity(0.5)),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'No earnings yet.\nStart hosting to earn credits.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EarningsBucket extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int credits;
  final int total;
  final bool loading;

  const _EarningsBucket({
    required this.label,
    required this.icon,
    required this.color,
    required this.credits,
    required this.total,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? credits / total : 0.0;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                if (loading)
                  const SizedBox(
                    height: 8,
                    child: LinearProgressIndicator(backgroundColor: AppColors.surfaceHigh),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$credits',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Text('credits',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
