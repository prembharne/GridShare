import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/glass_card.dart';

class ListingSettingsScreen extends StatefulWidget {
  const ListingSettingsScreen({super.key});

  @override
  State<ListingSettingsScreen> createState() => _ListingSettingsScreenState();
}

class _ListingSettingsScreenState extends State<ListingSettingsScreen> {
  final _rateHourController = TextEditingController(text: '8');
  final _rateKwhController = TextEditingController(text: '7');
  final _landmarkController = TextEditingController();
  final _slotController = TextEditingController();
  String _accessType = 'public';
  String _rateMode = 'hour';

  @override
  void dispose() {
    _rateHourController.dispose();
    _rateKwhController.dispose();
    _landmarkController.dispose();
    _slotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.hostAccent),
        title: const Text('Listing Settings', style: AppTextStyles.title),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Listing settings saved!'),
                  backgroundColor: AppColors.hostAccent,
                ),
              );
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: AppColors.hostAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Rate Configuration ──────────────────────────────────────
              Text('SET YOUR RATE', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                  .animate().fadeIn(duration: 400.ms),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                glow: true,
                glowColor: AppColors.hostAccent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RateModeChip(
                          label: 'Per Hour',
                          selected: true,
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _CreditInput(
                            controller: _rateHourController,
                            label: 'credits / hour',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Riders will see this rate on the map pin before booking.',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms, duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: AppSpacing.lg),

              // ── Location Details ────────────────────────────────────────
              Text('PIN LOCATION DETAILS', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                  .animate().fadeIn(delay: 150.ms, duration: 400.ms),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                child: Column(
                  children: [
                    _FormField(
                      controller: _landmarkController,
                      label: 'Landmark Notes for Rider',
                      hint: 'e.g. "Near B-Wing Lift, White Gate"',
                      icon: Icons.location_on_rounded,
                      accentColor: AppColors.hostAccent,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _FormField(
                      controller: _slotController,
                      label: 'Parking Slot Number',
                      hint: 'e.g. "B-12" or "Visitor Slot 4"',
                      icon: Icons.local_parking_rounded,
                      accentColor: AppColors.hostAccent,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: AppSpacing.lg),

              // ── Access Type ─────────────────────────────────────────────
              Text('ACCESS TYPE', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary))
                  .animate().fadeIn(delay: 250.ms, duration: 400.ms),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                child: Column(
                  children: [
                    _AccessOption(
                      icon: Icons.public_rounded,
                      title: 'Public',
                      subtitle: 'Anyone nearby can book your plug point.',
                      selected: _accessType == 'public',
                      onTap: () => setState(() => _accessType = 'public'),
                      accentColor: AppColors.hostAccent,
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    _AccessOption(
                      icon: Icons.lock_rounded,
                      title: 'Society Only',
                      subtitle: 'Restricted to verified private residents.',
                      selected: _accessType == 'private',
                      onTap: () => setState(() => _accessType = 'private'),
                      accentColor: AppColors.hostAccent,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RateModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.hostAccent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rSm),
          border: Border.all(
            color: selected ? AppColors.hostAccent : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? AppColors.hostAccent : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            )),
      ),
    );
  }
}

class _CreditInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _CreditInput({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.hostAccent,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.hostAccentSoft,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
                borderSide: const BorderSide(color: AppColors.hostAccent, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
                borderSide: BorderSide(color: AppColors.hostAccent.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
                borderSide: const BorderSide(color: AppColors.hostAccent, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
            )),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color accentColor;
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accentColor, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.rSm),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccessOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color accentColor;
  const _AccessOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rMd),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? accentColor.withValues(alpha: 0.2) : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppSpacing.rSm),
              ),
              child: Icon(icon, color: selected ? accentColor : AppColors.textMuted, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTextStyles.title.copyWith(
                        color: selected ? accentColor : AppColors.textPrimary,
                      )),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            AnimatedContainer(
              duration: 250.ms,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accentColor : AppColors.border,
                  width: 2,
                ),
                color: selected ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
              ),
              child: selected
                  ? Icon(Icons.check_rounded, color: accentColor, size: 14)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
