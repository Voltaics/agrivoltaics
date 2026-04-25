import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../../../../app_colors.dart';

class PestResult {
  final String prediction;
  final double confidence;
  PestResult({required this.prediction, required this.confidence});

  Color get confidenceColor {
    if (confidence > 0.85) return AppColors.success;
    if (confidence > 0.6) return AppColors.warning;
    return AppColors.error;
  }
}

class PestDetectionModel extends StatefulWidget {
  const PestDetectionModel({super.key});

  @override
  State<PestDetectionModel> createState() => _PestDetectionModelState();
}

class _PestDetectionModelState extends State<PestDetectionModel> with SingleTickerProviderStateMixin{
  XFile? _selectedXFile;
  PestResult? _result;
  bool _isLoading = false;
  String? _error;

  final ImagePicker _picker = ImagePicker();
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 90);
    if (image != null) {
      if (!mounted) return;
      setState(() {
        _selectedXFile = image;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedXFile == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null; // Clear previous result on new analysis
    });

    try {
      String baseUrl = 'https://pest-detection-api-593883469296.us-east4.run.app/pests_predict';
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        baseUrl = 'http://10.0.2.2:8080/pests_predict';
      }

      var request = http.MultipartRequest('POST', Uri.parse(baseUrl));

      if (kIsWeb) {
        final bytes = await _selectedXFile!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _selectedXFile!.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', _selectedXFile!.path));
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonDecoded = json.decode(responseData);

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _result = PestResult(
            prediction: jsonDecoded['prediction'],
            confidence: (jsonDecoded['confidence'] as num).toDouble(),
          );
        });
      } else {
        final errorMessage = jsonDecoded['error'] ?? jsonDecoded['detail'] ?? jsonDecoded['message'] ?? responseData;
        setState(() => _error = "Server Error (${response.statusCode}): $errorMessage");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Connection Failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset() => setState(() {
    _selectedXFile = null;
    _result = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    // Styling constants derived standard layout
    final scheme = Theme.of(context).colorScheme;
    final onSurfaceVar = scheme.onSurfaceVariant;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plant Pest Detection Scan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textOnLight),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload or capture pest image and then tap on Analyze Pest to start calculations '
              '(it might take a few minutes to finish). Currently, the AI model detects following '
              'pests: Adult Spotted Laternfly, Early Nypmh Spotted Lanternfly, Late Nymph Spotted Lanternfly, Green Leaf Hopper, and Japanese Beetle. '
              '(The model returns "No Pests" if it could not find any specific pests in the image.)',
              style: TextStyle(fontSize: 13, color: onSurfaceVar),
            ),
            const SizedBox(height: 16),
            // The main responsive grid
            _buildMainGrid(context),
          ],
        ),
      ),
    );
  }

  // Uses LayoutBuilder to handle orientation changes (Bug Fix 2 & 3)
  Widget _buildMainGrid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 700;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _buildImagePanel(context)),
            const SizedBox(width: 20),
            Expanded(flex: 5, child: _buildResultsPanel(context)),
          ],
        );
      }
      return Column(children: [
        _buildImagePanel(context),
        const SizedBox(height: 20),
        _buildResultsPanel(context),
      ]);
    });
  }

  Widget _buildImagePanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.camera_alt_rounded, label: 'Image Input'),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _pickImage(ImageSource.gallery),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 280,
              decoration: BoxDecoration(
                color: _selectedXFile == null ? AppColors.scaffoldBackground : Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedXFile == null
                      ? scheme.primary.withValues(alpha: 0.35)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedXFile == null
                  ? const _EmptyImagePreview()
                  : _ImagePreview(selectedXFile: _selectedXFile!),
            ),
          ),
          const SizedBox(height: 16),
          // Button row with standard spacing to prevent single-letter text
          Row(
            children: [
              Expanded(
                child: _OutlinedBtn(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OutlinedBtn(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
              ),
              if (_selectedXFile != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _OutlinedBtn(
                    icon: Icons.refresh_rounded,
                    label: 'Reset',
                    onTap: _reset,
                    color: scheme.error,
                  ),
                ),
              ]
            ],
          ),
          if (_selectedXFile != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _PrimaryBtn(
                label: _isLoading ? 'Analyzing...' : 'Analyze Pest',
                icon: _isLoading ? null : Icons.biotech_rounded,
                loading: _isLoading,
                onTap: _isLoading ? null : _analyzeImage,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.analytics_rounded, label: 'Analysis Results'),
          const SizedBox(height: 16),
          if (_isLoading)
            _LoadingState(animation: _pulseAnim)
          else if (_error != null)
            _ErrorState(message: _error!)
          else if (_result != null)
            _ResultContent(result: _result!)
          else
            const _EmptyResultState(),
        ],
      ),
    );
  }
}

// ── Image Handling Components ───────────────────────────────────────────────
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.selectedXFile});
  final XFile selectedXFile;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(selectedXFile.path, fit: BoxFit.contain, width: double.infinity);
    } else {
      return Image.file(File(selectedXFile.path), fit: BoxFit.contain, width: double.infinity);
    }
  }
}

class _EmptyImagePreview extends StatelessWidget {
  const _EmptyImagePreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(32)),
            child: Icon(Icons.upload_file_rounded, size: 32, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Click to upload image',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textOnLight),
        ),
        const SizedBox(height: 6),
        const Text(
          'JPG, PNG, WEBP supported',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ── Analysis Display Components ───────────────────────────────────────────────
class _ResultContent extends StatefulWidget {
  const _ResultContent({required this.result});
  final PestResult result;

  @override
  State<_ResultContent> createState() => _ResultContentState();
}

class _ResultContentState extends State<_ResultContent> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _barAnim = Tween<double>(begin: 0, end: widget.result.confidence).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _getConfidenceSeverity(double confidence) {
    if (confidence > 0.85) return 'High Confidence';
    if (confidence > 0.6) return 'Moderate Confidence';
    return 'Low Confidence';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: r.confidenceColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: r.confidenceColor),
              const SizedBox(width: 6),
              Text(
                _getConfidenceSeverity(r.confidence),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: r.confidenceColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MetricRow(label: 'Detected Pest', value: r.prediction),
        const Divider(color: Color(0xFFE5E7EB), height: 1),
        
        // Animated Confidence Bar section
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Confidence', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                  AnimatedBuilder(
                    animation: _barAnim,
                    builder: (_, __) => Text(
                      '${(_barAnim.value * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: r.confidenceColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AnimatedBuilder(
                  animation: _barAnim,
                  builder: (_, __) => LinearProgressIndicator(
                    value: _barAnim.value,
                    minHeight: 8,
                    backgroundColor: Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(r.confidenceColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFFE5E7EB), height: 1),
      ],
    );
  }
}

class _EmptyResultState extends StatelessWidget {
  const _EmptyResultState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.bug_report_rounded, size: 48, color: scheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              'No image analysed yet',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload a pest image and tap Analyse',
              style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: animation,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 20),
              const Text(
                'Analyzing pest image...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.error, fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Generic Reusable UI Containers consistent standard styling ────────────────────
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textOnLight)),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textOnLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  const _OutlinedBtn({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Explicitly define color or default to primary from theme
    final c = color ?? theme.colorScheme.primary;
    
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c, fontSize: 13), maxLines: 1),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        // Set minimum width to zero to allow responsive resizing by parent layout
        minimumSize: Size.zero, 
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, this.icon, this.loading = false, this.onTap});
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 18, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        disabledBackgroundColor: primary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}
