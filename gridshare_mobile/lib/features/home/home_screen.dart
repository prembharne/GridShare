import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../core/widgets/state_views.dart';
import '../../core/shaders/shader_canvas.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../features/wallet/topup_sheet.dart';
import 'outlet_detail_sheet.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Outlet>? _outlets;
  bool _loading = true;
  bool _failed = false;
  int _currentIndex = 0;

  /// Role state lifted here so the nav bar can react to it.
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _outlets = await ref.read(outletServiceProvider).nearby();
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Role-aware nav items ───────────────────────────────────────────────────
  List<BottomNavigationBarItem> get _navItems {
    if (_isHost) {
      return const [
        BottomNavigationBarItem(
          icon: Icon(Icons.power_rounded),
          label: 'My Listings',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_rounded),
          label: 'Service Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.manage_accounts_rounded),
          label: 'Host Panel',
        ),
      ];
    }
    return const [
      BottomNavigationBarItem(
        icon: Icon(Icons.near_me_rounded),
        label: 'Nearby',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.map_rounded),
        label: 'Maps',
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.person_rounded),
        label: 'My Account',
      ),
    ];
  }

  Color get _navAccent => _isHost ? AppColors.hostAccent : AppColors.accent;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    Widget body;
    switch (_currentIndex) {
      case 0:
        // Rider: Nearby list / Host: My Listings placeholder
        if (_isHost) {
          body = _HostListingsTab(accentColor: AppColors.hostAccent);
        } else {
          body = Stack(
            children: [
              Positioned.fill(
                child: ShaderCanvas(
                  spec: ShaderSpec.ripple(),
                  fallback: AppColors.surfaceGradient,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GradientText('Nearby', style: AppTextStyles.display)
                                  .animate()
                                  .fadeIn(duration: 600.ms)
                                  .slideX(begin: -0.2, curve: Curves.easeOutQuart),
                              Text('${_outlets?.length ?? 0} plugs around you',
                                      style: AppTextStyles.caption)
                                  .animate()
                                  .fadeIn(delay: 200.ms, duration: 600.ms),
                            ],
                          ),
                          const Spacer(),
                          if (user != null)
                            GestureDetector(
                              onTap: () => setState(() => _currentIndex = 2),
                              child: PulseGlow(
                                color: AppColors.accent,
                                minBlur: 8,
                                maxBlur: 20,
                                child: CircleAvatar(
                                  backgroundColor: AppColors.surfaceHigh,
                                  child: Text(user.name[0],
                                      style: const TextStyle(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const SkeletonList()
                          : _failed
                              ? StateView.error(onAction: _load)
                              : (_outlets == null || _outlets!.isEmpty)
                                  ? StateView.empty(onAction: _load)
                                  : _OutletList(
                                      outlets: _outlets!,
                                      onTap: (o) => _showSheet(o),
                                    ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        break;

      case 1:
        // Maps tab — real OpenFreeMap via MapLibre GL
        body = Stack(
          children: [
            // ── Real MapLibre Map ────────────────────────────────────
        // ── flutter_map with OpenFreeMap-compatible dark tiles ─────────────
            FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(20.5937, 78.9629), // India centre
                initialZoom: 4.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: _isHost
                      ? 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'
                      : 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.gridshare_mobile',
                  maxNativeZoom: 18,
                ),
                // Outlet marker layer (Rider only)
                if (!_isHost && _outlets != null)
                  MarkerLayer(
                    markers: _outlets!.map((o) {
                      // Scatter outlets around India centre for demo
                      final rnd  = (o.id.hashCode % 1000) / 1000;
                      final rnd2 = ((o.id.hashCode ~/ 7) % 1000) / 1000;
                      return Marker(
                        point: LatLng(
                          18.0 + rnd * 15,
                          72.0 + rnd2 * 20,
                        ),
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: o.available
                                ? AppColors.accent.withValues(alpha: 0.25)
                                : AppColors.dangerSoft,
                            border: Border.all(
                              color: o.available ? AppColors.accent : AppColors.danger,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (o.available ? AppColors.accent : AppColors.danger)
                                    .withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.electrical_services_rounded,
                            color: o.available ? AppColors.accent : AppColors.danger,
                            size: 18,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
            // ── Header overlay ────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.rMd),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(AppSpacing.rMd),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GradientText(
                                _isHost ? 'Host Map' : 'Maps',
                                style: AppTextStyles.display.copyWith(fontSize: 26),
                              ).animate().fadeIn(duration: 600.ms),
                              Text(
                                _isHost
                                    ? 'Your active listing zones'
                                    : 'Pulsing pins = charging slots',
                                style: AppTextStyles.caption,
                              ).animate().fadeIn(delay: 200.ms),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (user != null)
                      GestureDetector(
                        onTap: () => setState(() => _currentIndex = 2),
                        child: PulseGlow(
                          color: _navAccent,
                          minBlur: 8,
                          maxBlur: 20,
                          child: CircleAvatar(
                            backgroundColor: AppColors.surfaceHigh,
                            child: Text(user.name[0],
                                style: TextStyle(
                                    color: _navAccent,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
        break;

      case 2:
      default:
        // Profile / Account tab — pass role state + callback
        body = ProfileScreen(
          isHost: _isHost,
          onRoleChanged: (isHost) => setState(() => _isHost = isHost),
        );
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: body,
      floatingActionButton: _currentIndex != 2
          ? PulseGlow(
              color: _navAccent,
              minBlur: 14,
              maxBlur: 30,
              child: FloatingActionButton.extended(
                backgroundColor: _navAccent,
                foregroundColor: AppColors.background,
                elevation: 0,
                onPressed: () => _isHost ? null : context.push('/scan'),
                icon: Icon(_isHost ? Icons.add_location_alt_rounded : Icons.qr_code_2_rounded),
                label: Text(
                  _isHost ? 'Add Listing' : 'Scan',
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
            )
          : null,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: 300.ms,
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.75),
              border: Border(
                top: BorderSide(color: _navAccent.withValues(alpha: 0.25), width: 1),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: _navAccent,
              unselectedItemColor: AppColors.textMuted,
              selectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: _navItems,
            ),
          ),
        ).animate().slideY(begin: 1.0, duration: 800.ms, curve: Curves.easeOutExpo),
      ),
    );
  }

  void _showSheet(Outlet o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OutletDetailSheet(outlet: o),
    );
  }
}

// ── Host "My Listings" placeholder tab ─────────────────────────────────────
class _HostListingsTab extends StatelessWidget {
  final Color accentColor;
  const _HostListingsTab({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderCanvas(
            spec: ShaderSpec.aurora(),
            fallback: AppColors.surfaceGradient,
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GradientText('My Listings', style: AppTextStyles.display)
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideX(begin: -0.2, curve: Curves.easeOutQuart),
                Text('Manage your GridShare plug points',
                        style: AppTextStyles.caption)
                    .animate()
                    .fadeIn(delay: 200.ms),
                const SizedBox(height: AppSpacing.xl),
                GlassCard(
                  glow: true,
                  glowColor: accentColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(AppSpacing.rMd),
                            ),
                            child: Icon(Icons.add_home_work_rounded,
                                color: accentColor, size: 26),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No active listings',
                                  style: AppTextStyles.title),
                              Text('Add your first charging point',
                                  style: AppTextStyles.caption),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: AppColors.background,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.rMd),
                            ),
                            elevation: 0,
                          ),
                          icon:
                              const Icon(Icons.add_location_alt_rounded),
                          label: const Text('Add Listing',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
                const SizedBox(height: AppSpacing.lg),
                Text('QUICK STATS',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary))
                    .animate()
                    .fadeIn(delay: 250.ms),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _QuickStat(
                          label: 'Active Pins',
                          value: '0',
                          icon: Icons.electrical_services_rounded,
                          color: accentColor),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _QuickStat(
                          label: 'Sessions Today',
                          value: '0',
                          icon: Icons.ev_station_rounded,
                          color: accentColor),
                    ),
                  ],
                ).animate().fadeIn(delay: 300.ms),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _QuickStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(value,
              style: AppTextStyles.heading.copyWith(fontSize: 28, color: color)),
          Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── Outlet List (Rider) ─────────────────────────────────────────────────────
class _OutletList extends StatelessWidget {
  final List<Outlet> outlets;
  final ValueChanged<Outlet> onTap;
  const _OutletList({required this.outlets, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: outlets.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        final o = outlets[i];
        return GlassCard(
          glow: o.available,
          glowColor: o.available ? AppColors.accent : null,
          onTap: () => onTap(o),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: o.available ? AppColors.accentSoft : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rMd),
                ),
                child: Icon(
                  Icons.electrical_services_rounded,
                  color: o.available ? AppColors.accent : AppColors.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.name, style: AppTextStyles.title),
                    const SizedBox(height: 4),
                    Text(
                        '${o.distanceKm.toStringAsFixed(1)} km · ★ ${o.rating.toStringAsFixed(1)}',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${o.ratePerKwh.toStringAsFixed(0)} credits',
                      style: AppTextStyles.title
                          .copyWith(color: AppColors.accent)),
                  const Text('/kWh', style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        )
            .animate(delay: (80 * i).ms)
            .fadeIn(duration: 500.ms)
            .slideY(begin: 0.2, curve: Curves.easeOutQuart);
      },
    );
  }
}

/// Faux map grid so the shader reads as a "map" before Mapbox is wired.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const step = 48.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => false;
}
