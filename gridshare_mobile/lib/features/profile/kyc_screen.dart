// Copyright 2024 GridShare. All rights reserved.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_spacing.dart';

/// Screen for hosts to submit Aadhaar and PAN Card documents for KYC verification.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _panController = TextEditingController();

  bool _aadhaarFrontUploaded = false;
  bool _aadhaarBackUploaded = false;
  bool _panUploaded = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _aadhaarController.dispose();
    _panController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _aadhaarFrontUploaded && _aadhaarBackUploaded && _panUploaded;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload all required documents first.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    // Simulate submission request to backend
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() => _submitting = false);

    // Show Success Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.08),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFECFDF5),
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 40),
              ).animate().scale(duration: 400.ms, curve: Curves.bounceOut),
              const SizedBox(height: 20),
              const Text(
                'KYC Submitted Successfully',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your documents are under review. Your host dashboard payouts will activate shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context, true); // Return true to profile screen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Return to Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFAFAF9), // Warm white
            Color(0xFFEEF2FF), // Indigo 50
            Color(0xFFFAF5FF), // Purple 50
            Color(0xFFFDF2F8), // Pink 50
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'KYC Verification',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Identity Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 12),

                  // Name Field
                  _buildTextField(
                    controller: _nameController,
                    label: 'Full Name (as per Aadhaar)',
                    hint: 'Enter your legal name',
                    icon: Icons.person_outline_rounded,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ).animate().fadeIn(delay: 50.ms, duration: 400.ms),
                  const SizedBox(height: 12),

                  // Aadhaar Field
                  _buildTextField(
                    controller: _aadhaarController,
                    label: 'Aadhaar Card Number',
                    hint: '12-digit Aadhaar number',
                    icon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    validator: (v) => v == null || v.length != 12 ? 'Enter a valid 12-digit Aadhaar' : null,
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                  const SizedBox(height: 12),

                  // PAN Field
                  _buildTextField(
                    controller: _panController,
                    label: 'PAN Card Number',
                    hint: '10-character alphanumeric',
                    icon: Icons.credit_card_outlined,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.length != 10) return 'Enter a valid 10-character PAN';
                      final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
                      if (!regex.hasMatch(v.toUpperCase())) return 'Invalid PAN format (e.g. ABCDE1234F)';
                      return null;
                    },
                  ).animate().fadeIn(delay: 150.ms, duration: 400.ms),

                  const SizedBox(height: AppSpacing.xl),

                  const Text(
                    'Upload Documents',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                  const SizedBox(height: 12),

                  // Document uploads
                  Row(
                    children: [
                      Expanded(
                        child: _UploadSlot(
                          label: 'Aadhaar Front',
                          format: 'JPG, PNG up to 5MB',
                          onUploaded: () => setState(() => _aadhaarFrontUploaded = true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _UploadSlot(
                          label: 'Aadhaar Back',
                          format: 'JPG, PNG up to 5MB',
                          onUploaded: () => setState(() => _aadhaarBackUploaded = true),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
                  const SizedBox(height: 12),

                  _UploadSlot(
                    label: 'PAN Card Copy',
                    format: 'JPG, PNG, PDF up to 5MB',
                    onUploaded: () => setState(() => _panUploaded = true),
                  ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                  const SizedBox(height: AppSpacing.xxl),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canSubmit ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'Submit Verification',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ).animate().fadeIn(delay: 350.ms, duration: 400.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.02),
            blurRadius: 8,
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _UploadSlot extends StatefulWidget {
  final String label;
  final String format;
  final VoidCallback onUploaded;

  const _UploadSlot({required this.label, required this.format, required this.onUploaded});

  @override
  State<_UploadSlot> createState() => _UploadSlotState();
}

class _UploadSlotState extends State<_UploadSlot> {
  double _progress = 0.0;
  bool _uploading = false;
  String? _fileName;

  void _startUpload() async {
    if (_uploading || _fileName != null) return;
    setState(() {
      _uploading = true;
      _progress = 0.0;
    });

    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() {
        _progress = i / 10;
      });
    }

    setState(() {
      _uploading = false;
      _fileName = '${widget.label.toLowerCase().replaceAll(' ', '_')}.jpg';
    });
    widget.onUploaded();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _startUpload,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _fileName != null ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
            width: _fileName != null ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.02),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          children: [
            if (_fileName == null && !_uploading) ...[
              const Icon(Icons.cloud_upload_outlined, color: Color(0xFF4F46E5), size: 28),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.format,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ] else if (_uploading) ...[
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: _progress,
                  color: const Color(0xFF4F46E5),
                  strokeWidth: 3,
                  backgroundColor: const Color(0xFFF1F5F9),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Uploading ${(_progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
              ),
            ] else ...[
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              Text(
                _fileName!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
