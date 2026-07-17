import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/safety_banner.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../core/shaders/shader_canvas.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/services/api_service.dart';
import 'charging_ring.dart';
import 'energy_flow.dart';

class ChargingScreen extends ConsumerStatefulWidget {
  final Session session;
  const ChargingScreen({super.key, required this.session});

  @override
  ConsumerState<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends ConsumerState<ChargingScreen> {
  late Session _session;
  StreamSubscription<Telemetry>? _telemetrySub;
  Telemetry? _latestTelemetry;
  double _spent = 0;
  double _energy = 0;
  double _current = 0;
  double _voltage = 0;
  double _temp = 0;
  bool _tripped = false;
  bool _settling = false;
  bool _autoStopped = false;
  String? _safetyReason;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _spent = _session.spentCredits?.toDouble() ?? 0;
    _energy = _session.energyKwh ?? 0;
    _startTelemetry();
  }

  void _startTelemetry() {
    final api = ref.read(apiServiceProvider);
    // In production: connect to WebSocket for real-time telemetry
    // For now, poll the backend for latest telemetry
    _pollTelemetry(api);
  }

  Future<void> _pollTelemetry(ApiService api) async {
    while (mounted && !_settling && !_tripped) {
      try {
        // Backend doesn't have GET /telemetry yet; in production use WebSocket
        // This is a placeholder - real telemetry comes from device → Tuya → TimescaleDB → WS
        await Future.delayed(const Duration(seconds: 2));
        // Simulate progress for demo
        if (_session.depositCredits > 0) {
          _spent += 0.5;
          _energy += 0.03;
          _current = 12 + (_spent * 0.1);
          _voltage = 230;
          _temp = 30 + (_spent * 0.2);
          if (_spent >= _session.depositCredits) {
            _autoStopped = true;
            break;
          }
          if (mounted) setState(() {});
        }
      } catch (_) {
        // Ignore polling errors
      }
    }
    if (mounted && _autoStopped) _finish();
  }

  Future<void> _finish() async {
    if (_settling) return;
    setState(() => _settling = true);
    _telemetrySub?.cancel();
    try {
      final api = ref.read(apiServiceProvider);
      final settled = await api.stopSession(
        sessionId: _session.id,
        reason: _autoStopped ? 'auto_threshold' : 'user_stop',
        idempotencyKey: 'stop_${_session.id}',
      );
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) context.pop(settled);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settlement failed: $e'), backgroundColor: AppColors.danger),
      );
      setState(() => _settling = false);
    }
  }

  void _simulateTrip() {
    _telemetrySub?.cancel();
    setState(() {
      _tripped = true;
      _safetyReason = 'Over-temperature (>45°C)';
    });
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _session.depositCredits > 0 ? _spent / _session.depositCredits : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Living backdrop
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.pulse(color: AppColors.accent, progress: progress.clamp(0.0, 1.0)),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          Positioned.fill(
            child: ShaderCanvas(
              spec: ShaderSpec.spark(density: 0.4),
              fallback: AppColors.surfaceGradient,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.background.withValues(alpha: 0.45),
                    AppColors.background.withValues(alpha: 0.9),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_downward_rounded, color: AppColors.textSecondary),
                        onPressed: _settling ? null : () => context.pop(),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Charging', style: AppTextStyles.title),
                            Text('Live telemetry · Tuya → TimescaleDB', style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                      PulseGlow(
                        color: progress >= 1 ? AppColors.accent : AppColors.accentAlt,
                        minBlur: 6,
                        maxBlur: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (progress >= 1 ? AppColors.accent : AppColors.accentAlt)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                          child: Text(
                            progress >= 1 ? 'Complete' : '${(progress * 100).toInt()}%',
                            style: AppTextStyles.label.copyWith(
                              color: progress >= 1 ? AppColors.accent : AppColors.accentAlt,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_tripped)
                  SafetyBanner(
                    message: _safetyReason ?? 'Safety trip detected',
                    onDismiss: () => setState(() => _tripped = false),
                  ),
                // Charging ring
                Expanded(
                  child: Center(
                    child: FadeSlide(
                      delay: const Duration(milliseconds: 120),
                      child: ChargingRing(
                        progress: progress,
                        center: EnergyFlow25D(progress: progress),
                      ),
                    ),
                  ),
                ),
                // Live credits counter
                AnimatedCounter(
                  value: _spent,
                  prefix: '',
                  suffix: ' credits',
                  style: AppTextStyles.counter,
                ),
                Text('of ${_session.depositCredits} credits deposited', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.lg),
                // Readouts
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Readout(label: 'CURRENT', value: '${_current.toStringAsFixed(1)} A', color: AppColors.accent),
                      _Readout(label: 'VOLTAGE', value: '${_voltage.toStringAsFixed(0)} V', color: AppColors.accentAlt),
                      _Readout(
                        label: 'TEMP',
                        value: '${_temp.toStringAsFixed(0)}°C',
                        color: _temp > 45 ? AppColors.danger : AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                // Stop button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: _tripped
                      ? AppButton(
                          label: 'Acknowledge & close',
                          variant: AppButtonVariant.danger,
                          onPressed: () => context.pop(_session),
                        )
                      : AppButton(
                          label: _settling ? 'Settling…' : 'Stop charging',
                          onPressed: _settling ? null : _finish,
                          icon: Icons.stop_circle_rounded,
                        ),
                ),
                // Demo affordance
                TextButton(
                  onPressed: _tripped || _settling ? null : _simulateTrip,
                  child: Text('demo · simulate safety trip',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Readout({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.title.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}