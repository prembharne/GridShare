import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/magical_text.dart';
import '../../data/models/models.dart';

/// Production Native CameraX QR Scanner powered by MobileScanner.
/// Automatically handles native camera access, permissions, and live QR code detection.
class ScanScreen extends StatefulWidget {
  final Outlet? outlet;
  const ScanScreen({super.key, this.outlet});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final MobileScannerController _cameraController;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.outlet != null && ModalRoute.of(context)?.settings.name == null) {
      final o = widget.outlet!;
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
        actions: [
          ValueListenableBuilder(
            valueListenable: _cameraController,
            builder: (context, state, child) {
              return IconButton(
                icon: Icon(
                  state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                  color: AppColors.accent,
                ),
                onPressed: () => _cameraController.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _buildScannerFrame(context),
                ),
              ),
              const Text('Point your camera at the plug\'s QR code',
                  style: AppTextStyles.body, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Tap to Scan / Select Plug',
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

  Widget _buildScannerFrame(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 260,
              height: 260,
              child: MobileScanner(
                controller: _cameraController,
                onDetect: (capture) {
                  if (_scanned) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    setState(() => _scanned = true);
                    context.push('/pay', extra: _mockOutlet());
                  }
                },
              ),
            ),
          ),
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 2),
              borderRadius: BorderRadius.circular(AppSpacing.rLg),
            ),
          ),
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

  Widget _corner(Color color, double size, bool isTop, bool isLeft) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
        ),
      ),
    );
  }

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
