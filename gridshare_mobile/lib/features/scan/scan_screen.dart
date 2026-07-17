import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/magical_text.dart';
import '../../core/animations/animated_counter.dart';
import '../../data/models/models.dart';

/// QR scan flow. In production this is CameraX/ML Kit (mobile_scanner plugin).
/// Here the camera is simulated so the UI is fully runnable; a real scan just
/// resolves an `outlet_id` and routes to payment. Tapping "Simulate scan"
/// resolves a mock outlet.
class ScanScreen extends StatelessWidget {
  final Outlet? outlet;
  const ScanScreen({super.key, this.outlet});

  @override
  Widget build(BuildContext context) {
    // If launched from an outlet card, skip scanning and go straight to pay.
    // Guard against re-entrancy if the widget rebuilds before navigation fires.
    if (outlet != null && ModalRoute.of(context)?.settings.name == null) {
      final o = outlet!;
      Future.microtask(() {
        if (context.mounted) context.pushReplacement('/pay', extra: o);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => context.pop(),
        ),
        title: const GradientText('Scan to charge', style: AppTextStyles.title, shimmer: false),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _ScannerFrame(),
                ),
              ),
              const Text('Point your camera at the plug\'s QR code',
                  style: AppTextStyles.body, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Simulate scan',
                width: double.infinity,
                icon: Icons.camera_alt_rounded,
                onPressed: () => context.push('/pay', extra: _mockOutlet()),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  /// Animated scanner: glowing bracket corners + a sweeping laser line.
  Widget _ScannerFrame() {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.35), width: 2),
              borderRadius: BorderRadius.circular(AppSpacing.rLg),
            ),
          ),
          const Icon(Icons.qr_code_2_rounded, size: 80, color: AppColors.textMuted),
          ..._corners(),
          const _SweepLine(),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const c = AppColors.accent;
    const s = 18.0;
    return [
      Positioned(top: 8, left: 8, child: _corner(c, s, true, true)),
      Positioned(top: 8, right: 8, child: _corner(c, s, true, false)),
      Positioned(bottom: 8, left: 8, child: _corner(c, s, false, true)),
      Positioned(bottom: 8, right: 8, child: _corner(c, s, false, false)),
    ];
  }

  Widget _corner(Color color, double s, bool top, bool left) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          border: Border(
            top: top ? BorderSide(color: color, width: 3) : BorderSide.none,
            bottom: !top ? BorderSide(color: color, width: 3) : BorderSide.none,
            left: left ? BorderSide(color: color, width: 3) : BorderSide.none,
            right: !left ? BorderSide(color: color, width: 3) : BorderSide.none,
          ),
        ),
      );

  Outlet _mockOutlet() => const Outlet(
        id: 'outlet_demo',
        name: 'Lakeview Plug',
        hostName: 'Host A',
        lat: 12.9716,
        lng: 77.5946,
        distanceKm: 0.8,
        ratePerKwh: 16,
        available: true,
        connectorType: '16A BIS Smart Plug',
      );
}

/// A laser line that sweeps top→bottom repeatedly inside the scanner frame.
class _SweepLine extends StatefulWidget {
  const _SweepLine();

  @override
  State<_SweepLine> createState() => _SweepLineState();
}

class _SweepLineState extends State<_SweepLine> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        top: 12 + _ctrl.value * 236,
        left: 12,
        right: 12,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.accent.withValues(alpha: 0),
                AppColors.accent,
                AppColors.accent.withValues(alpha: 0),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.6),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
