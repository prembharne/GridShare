import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum AppButtonVariant { primary, ghost, danger }

class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.width,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with SingleTickerProviderStateMixin {
  // Micro-interaction: subtle scale on press.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.96,
    upperBound: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bg {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return AppColors.accent;
      case AppButtonVariant.danger:
        return AppColors.danger;
      case AppButtonVariant.ghost:
        return AppColors.surfaceHigh;
    }
  }

  Color get _fg {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return AppColors.background;
      case AppButtonVariant.danger:
        return Colors.white;
      case AppButtonVariant.ghost:
        return AppColors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _fg),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 20, color: _fg),
        if ((widget.icon != null || widget.loading) && widget.label.isNotEmpty)
          const SizedBox(width: AppSpacing.sm),
        if (widget.label.isNotEmpty)
          Text(
            widget.label,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _fg),
          ),
      ],
    );

    return ScaleTransition(
      scale: _ctrl,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.reverse(),
        onTapUp: (_) => _ctrl.forward(),
        onTapCancel: () => _ctrl.forward(),
        child: SizedBox(
          width: widget.width,
          child: ElevatedButton(
            onPressed: widget.loading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: _bg,
              foregroundColor: _fg,
              elevation: widget.variant == AppButtonVariant.primary ? 0 : 0,
              shadowColor: widget.variant == AppButtonVariant.primary ? AppColors.accent : null,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
