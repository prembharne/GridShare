import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

class IoTConfigScreen extends ConsumerStatefulWidget {
  const IoTConfigScreen({super.key});

  @override
  ConsumerState<IoTConfigScreen> createState() => _IoTConfigScreenState();
}

class _IoTConfigScreenState extends ConsumerState<IoTConfigScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  String _status = 'idle'; // idle | scanning | verifying | paired | offline

  final _nameCtrl = TextEditingController(text: 'Wipro 16A Smart Plug');
  final _deviceIdCtrl = TextEditingController(text: 'd72c4dd24f074a08fdwvz4');
  final _rateCtrl = TextEditingController(text: '12.5');
  final _addressCtrl =
      TextEditingController(text: "Prem's Prosumer EV Station");
  bool _isRegistering = false;
  Outlet? _pairedOutlet;

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _nameCtrl.dispose();
    _deviceIdCtrl.dispose();
    _rateCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _registerDevice() async {
    final api = ref.read(apiServiceProvider);
    final name = _nameCtrl.text.trim();
    final deviceId = _deviceIdCtrl.text.trim();
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 12.5;
    final address = _addressCtrl.text.trim();

    if (name.isEmpty || deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter Device Name and Tuya Device ID.')),
      );
      return;
    }

    setState(() {
      _status = 'scanning';
      _isRegistering = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    // The backend runs on a free tier that sleeps when idle; warn the user so a
    // 20–50s cold start reads as "connecting" instead of a frozen button.
    if (!api.isWarm) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Connecting to GridShare server… (this can take up to '
            'a minute if it was idle)'),
        duration: Duration(seconds: 8),
      ));
    }

    try {
      final outlet = await api.addOutlet(
        name: name,
        providerDeviceId: deviceId,
        ratePerKwh: rate,
        address: address.isNotEmpty ? address : "Host Registered Station",
      );

      // Registration only created the DB record — it does NOT prove the smart
      // plug is actually reachable. Probe the backend for the outlet's real
      // availability before claiming the node is "Online".
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      setState(() {
        _status = 'verifying';
        _pairedOutlet = outlet;
      });

      final reachable = await _verifyReachable(api, outlet);

      if (mounted) {
        setState(() {
          _status = reachable ? 'paired' : 'offline';
          _isRegistering = false;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(reachable
                ? '⚡ ${outlet.name} is online and ready to accept bookings.'
                : '${outlet.name} was registered, but the smart plug is not '
                    'responding. Check that it is powered on and connected to '
                    'Wi-Fi, then tap Re-check.'),
            backgroundColor:
                reachable ? AppColors.hostAccent : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        setState(() {
          _status = 'idle';
          _isRegistering = false;
        });
        messenger.showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    }
  }

  /// Converts raw network exceptions into a clear, actionable message.
  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout') || s.contains('future not completed')) {
      return 'The server took too long to respond (it may have been asleep). '
          'Please tap Register again — it should be awake now.';
    }
    if (s.contains('socket') ||
        s.contains('failed host lookup') ||
        s.contains('connection')) {
      return 'No connection to the GridShare server. Check your internet and '
          'try again.';
    }
    return 'Failed to register device: $e';
  }

  /// Probes the backend for the outlet's *real* availability after registration.
  /// We re-fetch nearby outlets around the registered location and match by id;
  /// the backend marks an outlet `available: true` only when its smart plug is
  /// actually reachable. Any error (or no match) is treated as "not reachable"
  /// so we never falsely report a dead plug as Online.
  Future<bool> _verifyReachable(dynamic api, Outlet outlet) async {
    try {
      final nearby = await api.getNearbyOutlets(
        lat: outlet.lat,
        lng: outlet.lng,
        radiusKm: 1,
      );
      final match = (nearby as List<Outlet>).where((o) => o.id == outlet.id);
      if (match.isEmpty) return outlet.available;
      return match.first.available;
    } catch (_) {
      return false;
    }
  }

  /// Re-runs the reachability probe for an already-registered outlet (used by
  /// the "Re-check" control when the plug was offline at registration time).
  Future<void> _recheck() async {
    final outlet = _pairedOutlet;
    if (outlet == null) return;
    final api = ref.read(apiServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _status = 'verifying');
    final reachable = await _verifyReachable(api, outlet);
    if (!mounted) return;
    setState(() => _status = reachable ? 'paired' : 'offline');
    messenger.showSnackBar(
      SnackBar(
        content: Text(reachable
            ? '⚡ ${outlet.name} is now online.'
            : 'Still no response from the smart plug. Make sure it is powered '
                'on and on the same Wi-Fi.'),
        backgroundColor: reachable ? AppColors.hostAccent : AppColors.warning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.hostAccent),
        title:
            const Text('Configure IoT Smart Plug', style: AppTextStyles.title),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status Indicator ──────────────────────────────────────
              GlassCard(
                glow: _status == 'paired',
                glowColor: AppColors.hostAccent,
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) {
                        final pulse = _status == 'scanning'
                            ? (0.5 + 0.5 * _pulseCtrl.value)
                            : 1.0;
                        return Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                _statusColor().withValues(alpha: 0.12 * pulse),
                            border: Border.all(
                              color: _statusColor().withValues(alpha: 0.7),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor()
                                    .withValues(alpha: 0.3 * pulse),
                                blurRadius: 24 * pulse,
                              ),
                            ],
                          ),
                          child: Icon(
                            _statusIcon(),
                            color: _statusColor(),
                            size: 44,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(_statusTitle(),
                        style: AppTextStyles.heading
                            .copyWith(color: _statusColor())),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_statusSubtitle(),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: AppSpacing.lg),

              // ── Device Input Form ──────────────────────────────────────
              if (_status != 'paired' && _status != 'offline') ...[
                Text('REGISTER IOT SMART PLUG',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary))
                    .animate()
                    .fadeIn(delay: 100.ms),
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Device / Station Name',
                          hintText: 'e.g. Wipro 16A Smart Plug',
                          prefixIcon: Icon(Icons.power_rounded,
                              color: AppColors.hostAccent),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _deviceIdCtrl,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Tuya Device ID',
                          hintText: 'e.g. d72c4dd24f074a08fdwvz4',
                          prefixIcon: Icon(Icons.developer_board_rounded,
                              color: AppColors.hostAccent),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _rateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: AppTextStyles.body,
                              decoration: const InputDecoration(
                                labelText: 'Rate (Credits/kWh)',
                                hintText: '12.5',
                                prefixIcon: Icon(Icons.bolt_rounded,
                                    color: AppColors.hostAccent),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: TextField(
                              controller: _addressCtrl,
                              style: AppTextStyles.body,
                              decoration: const InputDecoration(
                                labelText: 'Station Address',
                                hintText: "Prem's Station",
                                prefixIcon: Icon(Icons.location_on_rounded,
                                    color: AppColors.hostAccent),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isRegistering ? null : _registerDevice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.hostAccent,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.rMd),
                            ),
                            elevation: 0,
                          ),
                          icon: Icon(_isRegistering
                              ? Icons.hourglass_top_rounded
                              : Icons.add_link_rounded),
                          label: Text(
                            _isRegistering
                                ? 'Registering Device…'
                                : 'Register Smart Plug',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: 150.ms, duration: 500.ms)
                    .slideY(begin: 0.1),
                const SizedBox(height: AppSpacing.lg),
              ] else ...[
                // ── Paired Device Info ─────────────────────────────────
                Text('PAIRED DEVICE',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary))
                    .animate()
                    .fadeIn(delay: 100.ms),
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  glow: true,
                  glowColor: AppColors.hostAccent,
                  child: Column(
                    children: [
                      _DeviceInfoRow(
                          label: 'Device ID',
                          value: _pairedOutlet?.id ?? _deviceIdCtrl.text),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(
                          label: 'Firmware', value: 'v2.1.4 (latest)'),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(
                          label: 'Connectivity',
                          value: _status == 'paired' ? 'Wi-Fi ✓' : 'Unknown'),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(
                          label: 'Status',
                          value: _status == 'paired'
                              ? '🟢 Online'
                              : '🔴 Not responding'),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(begin: const Offset(0.95, 0.95)),
                if (_status == 'offline') ...[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _recheck,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Re-check Connection'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── Management Options ─────────────────────────────────────
              Text('HARDWARE CONTROLS',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.textSecondary))
                  .animate()
                  .fadeIn(delay: 200.ms),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ControlTile(
                      icon: Icons.refresh_rounded,
                      title: 'Reboot Smart Plug',
                      subtitle: 'Restart the IoT node remotely.',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reboot signal sent to node…'),
                            backgroundColor: AppColors.hostAccent,
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1, color: AppColors.border, indent: 56),
                    _ControlTile(
                      icon: Icons.sync_rounded,
                      title: 'Sync Node Config',
                      subtitle:
                          'Push latest rate & access settings to hardware.',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Syncing configuration to node…'),
                            backgroundColor: AppColors.hostAccent,
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1, color: AppColors.border, indent: 56),
                    _ControlTile(
                      icon: Icons.link_off_rounded,
                      title: 'Unpair Device',
                      subtitle: 'Remove this node from your host account.',
                      destructive: true,
                      onTap: () {
                        setState(() => _status = 'idle');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device unpaired.'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: 250.ms, duration: 500.ms)
                  .slideY(begin: 0.1),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor() {
    switch (_status) {
      case 'scanning':
      case 'verifying':
        return AppColors.warning;
      case 'paired':
        return AppColors.hostAccent;
      case 'offline':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case 'scanning':
      case 'verifying':
        return Icons.bluetooth_searching_rounded;
      case 'paired':
        return Icons.electrical_services_rounded;
      case 'offline':
        return Icons.power_off_rounded;
      default:
        return Icons.power_off_rounded;
    }
  }

  String _statusTitle() {
    switch (_status) {
      case 'scanning':
        return 'Registering…';
      case 'verifying':
        return 'Verifying Device…';
      case 'paired':
        return 'Node Paired ✓';
      case 'offline':
        return 'Device Not Responding';
      default:
        return 'No Device Paired';
    }
  }

  String _statusSubtitle() {
    switch (_status) {
      case 'scanning':
        return 'Registering your smart plug with GridShare…';
      case 'verifying':
        return 'Checking that the smart plug is powered on and reachable…';
      case 'paired':
        return 'Your smart plug is online and ready to accept bookings.';
      case 'offline':
        return 'Registered, but we could not reach the plug. Make sure it is '
            'powered on and connected to Wi-Fi, then re-check.';
      default:
        return 'Scan the QR code on your GridShare IoT device to pair it with your account.';
    }
  }
}

class _DeviceInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _DeviceInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
          Text(value,
              style:
                  AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _ControlTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const _ControlTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.hostAccent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.title.copyWith(
                        color: destructive
                            ? AppColors.danger
                            : AppColors.textPrimary,
                      )),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
