// Copyright 2024 GridShare. All rights reserved.

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';


import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../profile/profile_screen.dart';
import '../profile/iot_config_screen.dart';
import 'outlet_detail_sheet.dart';

/// Redesigned Home Screen utilizing light/pastel premium aesthetics.
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
  Outlet? _selectedRouteDestination;
  List<LatLng> _routePoints = [];
  bool _routeLoading = false;

  LatLng _userLocation = const LatLng(18.5204, 73.8567); // Default location
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
    _fetchLiveLocation();
  }

  Future<void> _fetchLiveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null && mounted) {
            setState(() {
              _userLocation = LatLng(lastPos.latitude, lastPos.longitude);
            });
            _mapController.move(_userLocation, 15.0);
          }

          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          );
          if (mounted) {
            setState(() {
              _userLocation = LatLng(pos.latitude, pos.longitude);
            });
            _mapController.move(_userLocation, 15.0);
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Live location error: $e');
    }

    // Fallback to HTTPS IP geolocation if GPS is unavailable
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null && mounted) {
          setState(() {
            _userLocation = LatLng(lat, lon);
          });
          _mapController.move(_userLocation, 14.0);
        }
      }
    } catch (_) {}
  }



  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
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
    if (_isHost) {
      switch (_currentIndex) {
        case 0:
          body = _HostListingsTab(accentColor: _navAccent);
          break;
        case 1:
        default:
          body = ProfileScreen(
            isHost: _isHost,
            onRoleChanged: (isHost) {
              setState(() {
                _isHost = isHost;
                _currentIndex = isHost ? 1 : 2;
              });
            },
          );
          break;
      }
    } else {
      switch (_currentIndex) {
        case 0:
          body = Stack(
            children: [
              // Soft background ambient orbs
              Positioned(
                top: -80, right: -80,
                child: Container(
                  width: 280, height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                bottom: -100, left: -60,
                child: Container(
                  width: 320, height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentBlue.withValues(alpha: 0.08),
                  ),
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
                              const Text(
                                'Nearby',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.displayFamily,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.5,
                                ),
                              ).animate()
                               .fadeIn(duration: 500.ms)
                               .slideX(begin: -0.15, curve: Curves.easeOutCubic),
                              Text(
                                '${_outlets?.length ?? 0} plugs around you',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ).animate()
                               .fadeIn(delay: 150.ms, duration: 500.ms),
                            ],
                          ),
                          const Spacer(),
                          if (user != null)
                            GestureDetector(
                              onTap: () => setState(() => _currentIndex = 2),
                              child: CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.surfaceHigh,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _navAccent.withValues(alpha: 0.5)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      user.name[0],
                                      style: TextStyle(
                                        color: _navAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Scaffold(
                              backgroundColor: Colors.transparent,
                              body: SkeletonList(),
                            )
                          : _failed
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textMuted),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Failed to load nearby plugs',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                      ),
                                      const SizedBox(height: 8),
                                      ElevatedButton(
                                        onPressed: _load,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _navAccent,
                                          foregroundColor: AppColors.background,
                                        ),
                                        child: const Text('Try Again'),
                                      )
                                    ],
                                  ),
                                )
                              : (_outlets == null || _outlets!.isEmpty)
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.pin_drop_outlined, size: 64, color: AppColors.textMuted),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'No plugs nearby right now',
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                          ),
                                          const SizedBox(height: 8),
                                          ElevatedButton(
                                            onPressed: _load,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _navAccent,
                                              foregroundColor: AppColors.background,
                                            ),
                                            child: const Text('Refresh'),
                                          )
                                        ],
                                      ),
                                    )
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
          break;

      case 1:
        // Maps tab — bright voyager theme map
        body = Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _userLocation,
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.gridshare_mobile',
                  maxNativeZoom: 18,
                ),
                // Outlet marker layer
                if (!_isHost && _outlets != null)
                  MarkerLayer(
                    markers: _outlets!.map((o) {
                      return Marker(
                        point: _getOutletLocation(o),
                        width: 38,
                        height: 38,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showSheet(o),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: o.available
                                  ? AppColors.accentSoft
                                  : AppColors.dangerSoft,
                              border: Border.all(
                                color: o.available ? AppColors.accent : AppColors.danger,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (o.available ? AppColors.accent : AppColors.danger)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.electrical_services_rounded,
                              color: o.available ? AppColors.accent : AppColors.danger,
                              size: 18,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                // Current location blue dot
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF007AFF),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Road route polyline from OSRM
                if (!_isHost && _routePoints.isNotEmpty)
                  PolylineLayer<Object>(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: AppColors.accent,
                        strokeWidth: 5.0,
                        borderColor: AppColors.accentBlue,
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );

        // Add route-loading banner on top of map
        if (_routeLoading) {
          body = Stack(
            children: [
              body,
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                      boxShadow: AppSpacing.glow(color: AppColors.accent, strength: 0.25),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Finding best route...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        break;

      case 2:
      default:
        body = ProfileScreen(
          isHost: _isHost,
          onRoleChanged: (isHost) {
            setState(() {
              _isHost = isHost;
              _currentIndex = isHost ? 1 : 2;
            });
          },
        );
        break;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surface,     // #161F30 — subtle lift at top
            AppColors.background,  // #0B0F19 — deep navy base
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: body,
        floatingActionButton: (_isHost ? _currentIndex == 0 : _currentIndex != 2)
            ? FloatingActionButton.extended(
                backgroundColor: _navAccent,
                foregroundColor: AppColors.background,
                elevation: 4,
                onPressed: () => _isHost ? null : context.push('/scan'),
                icon: Icon(_isHost ? Icons.add_location_alt_rounded : Icons.qr_code_2_rounded),
                label: Text(
                  _isHost ? 'Add Listing' : 'Scan',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              )
            : null,
        bottomNavigationBar: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: 300.ms,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.85),
                border: const Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: _navAccent,
                unselectedItemColor: AppColors.textMuted,
                selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                unselectedLabelStyle: const TextStyle(fontSize: 11),
                items: _navItems,
              ),
            ),
          ),
        ).animate().slideY(begin: 1.0, duration: 800.ms, curve: Curves.easeOutExpo),
      ),
    );
  }

  Future<void> _getDirections(Outlet o) async {
    setState(() {
      _selectedRouteDestination = o;
      _routePoints = [];
      _routeLoading = true;
      _currentIndex = 1;
    });

    try {
      const origin = LatLng(20.5937, 78.9629); // Simulated current location
      final dest = _getOutletLocation(o);
      // OSRM public routing API — free, no key needed
      final url = 'http://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};'
          '${dest.longitude},${dest.latitude}'
          '?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        final points = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (mounted) setState(() => _routePoints = points);
      }
    } catch (_) {
      // Fallback: draw straight line if routing fails
      if (mounted) {
        setState(() => _routePoints = [
          const LatLng(20.5937, 78.9629),
          _getOutletLocation(o),
        ]);
      }
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  LatLng _getOutletLocation(Outlet o) {
    final rnd = (o.id.hashCode % 1000) / 1000;
    final rnd2 = ((o.id.hashCode ~/ 7) % 1000) / 1000;
    return LatLng(18.0 + rnd * 15, 72.0 + rnd2 * 20);
  }

  void _showSheet(Outlet o) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OutletDetailSheet(
        outlet: o,
        onDirectionPressed: () => _getDirections(o),
      ),
    );
  }
}

// ── Host "My Listings" tab ──────────────────────────────────────────────────
class _HostListingsTab extends ConsumerStatefulWidget {
  final Color accentColor;
  const _HostListingsTab({required this.accentColor});

  @override
  ConsumerState<_HostListingsTab> createState() => _HostListingsTabState();
}

class _HostListingsTabState extends ConsumerState<_HostListingsTab> {
  List<Outlet>? _outlets;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchHostListings();
  }

  Future<void> _fetchHostListings() async {
    try {
      final api = ref.read(apiServiceProvider);
      final outlets = await api.getNearbyOutlets(lat: 19.0760, lng: 72.8777);
      if (mounted) setState(() => _outlets = outlets);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAddListing() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => IoTConfigScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: anim.drive(
            Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
    ).then((_) => _fetchHostListings());
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.accentColor;
    final activeCount = _outlets?.length ?? 0;

    return Stack(
      children: [
        Positioned(
          top: -100, right: -100,
          child: Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.hostAccent.withValues(alpha: 0.12),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My Listings',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.2, curve: Curves.easeOutQuart),
                        const Text(
                          'Manage your GridShare plug points',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ).animate().fadeIn(delay: 200.ms),
                      ],
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: _openAddListing,
                      icon: const Icon(Icons.add_location_alt_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: accentColor.withValues(alpha: 0.15),
                        foregroundColor: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (activeCount == 0)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppSpacing.glow(color: accentColor, strength: 0.08),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(Icons.add_home_work_rounded, color: accentColor, size: 26),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No active listings',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Text(
                                  'Add your first charging point',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _openAddListing,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.add_location_alt_rounded),
                            label: const Text('Add Listing', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1)
                else
                  Column(
                    children: _outlets!.map((outlet) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                          boxShadow: AppSpacing.glowSoft(color: accentColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.power_rounded, color: accentColor, size: 26),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        outlet.name,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Device ID: d72c4dd24f074a08fdwvz4',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('🟢 Online', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)),
                                ),
                              ],
                            ),
                            const Divider(height: 24, color: AppColors.border),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Rate: ${outlet.ratePerKwh} credits/kWh', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                Text(outlet.connectorType ?? '16A Socket', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'QUICK STATS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                ).animate().fadeIn(delay: 250.ms),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _QuickStat(
                        label: 'Active Pins',
                        value: activeCount.toString(),
                        icon: Icons.electrical_services_rounded,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _QuickStat(
                        label: 'Sessions Today',
                        value: '0',
                        icon: Icons.ev_station_rounded,
                        color: accentColor,
                      ),
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
  const _QuickStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppSpacing.glowSoft(color: color),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      itemCount: outlets.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        final o = outlets[i];
        final statusColor = o.available ? AppColors.accent : AppColors.danger;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.rLg),
            border: Border.all(color: AppColors.border),
            boxShadow: AppSpacing.glowSoft(color: statusColor),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(o),
              borderRadius: BorderRadius.circular(AppSpacing.rLg),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.rSm),
                        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                      ),
                      child: Icon(
                        Icons.electrical_services_rounded,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.title.copyWith(fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.near_me_rounded, size: 13, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                '${o.distanceKm.toStringAsFixed(1)} km',
                                style: AppTextStyles.body.copyWith(fontSize: 13),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                              const SizedBox(width: 2),
                              Text(
                                o.rating.toStringAsFixed(1),
                                style: AppTextStyles.body.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Text(
                              o.available ? 'Available' : 'In use',
                              style: AppTextStyles.label.copyWith(
                                color: statusColor,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${o.ratePerKwh.toStringAsFixed(0)} cr',
                          style: AppTextStyles.title.copyWith(
                            fontSize: 18,
                            color: AppColors.accent,
                          ),
                        ),
                        Text('/kWh', style: AppTextStyles.caption),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
         .animate(delay: (80 * i).ms)
         .fadeIn(duration: 450.ms)
         .slideY(begin: 0.15, curve: Curves.easeOutCubic);
      },
    );
  }
}
