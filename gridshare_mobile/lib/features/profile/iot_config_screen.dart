import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';

class IoTConfigScreen extends StatefulWidget {
  const IoTConfigScreen({super.key});

  @override
  State<IoTConfigScreen> createState() => _IoTConfigScreenState();
}

class _IoTConfigScreenState extends State<IoTConfigScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  String _status = 'idle'; // idle | scanning | paired

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() => _status = 'scanning');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _status = 'paired');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.hostAccent),
        title: const Text('Configure IoT Smart Plug', style: AppTextStyles.title),
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
                        final pulse = _status == 'scanning' ? (0.5 + 0.5 * _pulseCtrl.value) : 1.0;
                        return Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor().withValues(alpha: 0.12 * pulse),
                            border: Border.all(
                              color: _statusColor().withValues(alpha: 0.7),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor().withValues(alpha: 0.3 * pulse),
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
                        style: AppTextStyles.heading.copyWith(color: _statusColor())),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_statusSubtitle(),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption),
                  ],
                ),
              ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),
              const SizedBox(height: AppSpacing.lg),

              // ── QR Scan Trigger ───────────────────────────────────────
              if (_status != 'paired') ...[
                Text('PAIR YOUR DEVICE', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                    .animate().fadeIn(delay: 100.ms),
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.hostAccentSoft,
                              borderRadius: BorderRadius.circular(AppSpacing.rSm),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded,
                                color: AppColors.hostAccent, size: 24),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Scan QR on IoT Hardware',
                                    style: AppTextStyles.title),
                                Text('Point your camera at the QR code on the device.',
                                    style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _status == 'scanning' ? null : _startScan,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.hostAccent,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.rMd),
                            ),
                            elevation: 0,
                          ),
                          icon: Icon(_status == 'scanning'
                              ? Icons.hourglass_top_rounded
                              : Icons.qr_code_2_rounded),
                          label: Text(
                            _status == 'scanning' ? 'Searching…' : 'Scan QR Code',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.1),
                const SizedBox(height: AppSpacing.lg),
              ] else ...[
                // ── Paired Device Info ─────────────────────────────────
                Text('PAIRED DEVICE', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                    .animate().fadeIn(delay: 100.ms),
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  glow: true,
                  glowColor: AppColors.hostAccent,
                  child: Column(
                    children: [
                      _DeviceInfoRow(label: 'Device ID', value: 'GS-NODE-0x4A2F'),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(label: 'Firmware', value: 'v2.1.4 (latest)'),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(label: 'Connectivity', value: 'Wi-Fi ✓'),
                      const Divider(height: 1, color: AppColors.border),
                      _DeviceInfoRow(label: 'Status', value: '🟢 Online'),
                    ],
                  ),
                ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── Management Options ─────────────────────────────────────
              Text('HARDWARE CONTROLS', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                  .animate().fadeIn(delay: 200.ms),
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
                    const Divider(height: 1, color: AppColors.border, indent: 56),
                    _ControlTile(
                      icon: Icons.sync_rounded,
                      title: 'Sync Node Config',
                      subtitle: 'Push latest rate & access settings to hardware.',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Syncing configuration to node…'),
                            backgroundColor: AppColors.hostAccent,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, color: AppColors.border, indent: 56),
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
              ).animate().fadeIn(delay: 250.ms, duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor() {
    switch (_status) {
      case 'scanning': return AppColors.warning;
      case 'paired':   return AppColors.hostAccent;
      default:         return AppColors.textMuted;
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case 'scanning': return Icons.bluetooth_searching_rounded;
      case 'paired':   return Icons.electrical_services_rounded;
      default:         return Icons.power_off_rounded;
    }
  }

  String _statusTitle() {
    switch (_status) {
      case 'scanning': return 'Searching…';
      case 'paired':   return 'Node Paired ✓';
      default:         return 'No Device Paired';
    }
  }

  String _statusSubtitle() {
    switch (_status) {
      case 'scanning': return 'Looking for GridShare IoT hardware nearby via Bluetooth & Wi-Fi.';
      case 'paired':   return 'Your smart plug is online and ready to accept bookings.';
      default:         return 'Scan the QR code on your GridShare IoT device to pair it with your account.';
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.title.copyWith(
                    color: destructive ? AppColors.danger : AppColors.textPrimary,
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
