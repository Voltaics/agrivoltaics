import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../../app_colors.dart';
import 'plant_disease_api_config.dart';
import 'plant_image_preview_io.dart' if (dart.library.html) 'plant_image_preview_web.dart' as preview;

class DiseaseTopEntry {
  const DiseaseTopEntry({required this.disease, required this.confidence});

  final String disease;
  final double confidence;
}

class DiseaseResult {
  DiseaseResult({
    required this.disease,
    required this.confidence,
    this.top3 = const [],
  })  : severity = confidence > 0.85
            ? 'High Confidence'
            : confidence > 0.6
                ? 'Moderate Confidence'
                : 'Low Confidence';

  final String disease;
  final double confidence;
  final List<DiseaseTopEntry> top3;
  final String severity;

  Color get confidenceColor {
    if (confidence > 0.85) return AppColors.success;
    if (confidence > 0.6) return AppColors.warning;
    return AppColors.error;
  }
}

List<DiseaseTopEntry> _parseTop3(Object? raw) {
  if (raw is! List<dynamic>) return const [];
  final out = <DiseaseTopEntry>[];
  for (final e in raw) {
    if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      final d = m['disease'];
      final c = m['confidence'];
      if (d is String && c is num) {
        out.add(DiseaseTopEntry(disease: d, confidence: c.toDouble()));
      }
    }
  }
  return out;
}

class PlantDiseaseDetectionModel extends StatefulWidget {
  const PlantDiseaseDetectionModel({super.key});

  @override
  State<PlantDiseaseDetectionModel> createState() =>
      _PlantDiseaseDetectionModelState();
}

class _PlantDiseaseDetectionModelState extends State<PlantDiseaseDetectionModel>
    with SingleTickerProviderStateMixin {
  XFile? _selectedImage;
  DiseaseResult? _result;
  bool _isLoading = false;
  String? _error;
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1024,
    );
    if (picked != null) {
      setState(() {
        _selectedImage = picked;
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final request = http.MultipartRequest('POST', Uri.parse(plantDiseasePredictUrl));
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: _selectedImage!.name,
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _result = DiseaseResult(
            disease: json['disease'] as String,
            confidence: (json['confidence'] as num).toDouble(),
            top3: _parseTop3(json['top3']),
          );
        });
      } else {
        if (!mounted) return;
        setState(() => _error = 'Server error (${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to connect to analysis server.\n$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset() => setState(() {
        _selectedImage = null;
        _result = null;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final onVar = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plant Disease Detection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload or capture plant image and then tap on Analyze Plant to start calculations '
              '(it might take a few minutes to finish). Currently, the AI model detects following '
              'diseases: Black Rot, Black Measles, Leaf Blight, Downey Mildew, Powdery Mildew',
              style: TextStyle(color: onVar),
            ),
            const SizedBox(height: 16),
            _buildMainGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMainGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
        return Column(
          children: [
            _buildImagePanel(context),
            const SizedBox(height: 20),
            _buildResultsPanel(context),
          ],
        );
      },
    );
  }

  Widget _buildImagePanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.camera_alt_rounded,
            label: 'Image Input',
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _pickImage(ImageSource.gallery),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 280,
              decoration: BoxDecoration(
                color: _selectedImage == null
                    ? AppColors.scaffoldBackground
                    : Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedImage == null
                      ? scheme.primary.withValues(alpha: 0.35)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedImage == null
                  ? const _DropZoneContent()
                  : _ImagePreview(file: _selectedImage!),
            ),
          ),
          const SizedBox(height: 16),
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
              if (!kIsWeb) ...[
                Expanded(
                  child: _OutlinedBtn(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (_selectedImage != null)
                Expanded(
                  child: _OutlinedBtn(
                    icon: Icons.refresh_rounded,
                    label: 'Reset',
                    onTap: _reset,
                    color: AppColors.error,
                  ),
                ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _PrimaryBtn(
                label: _isLoading ? 'Analyzing...' : 'Analyze Plant',
                icon: _isLoading ? null : Icons.biotech_rounded,
                loading: _isLoading,
                onTap: _isLoading ? null : _analyzeImage,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.analytics_rounded,
            label: 'Analysis Results',
          ),
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

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) => preview.plantImagePreview(file);
}

class _DropZoneContent extends StatelessWidget {
  const _DropZoneContent();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Icon(
            Icons.upload_file_rounded,
            size: 32,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Click to upload a plant image',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textOnLight,
          ),
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

class _ResultContent extends StatefulWidget {
  const _ResultContent({required this.result});

  final DiseaseResult result;

  @override
  State<_ResultContent> createState() => _ResultContentState();
}

class _ResultContentState extends State<_ResultContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _barAnim = Tween<double>(
      begin: 0,
      end: widget.result.confidence,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    const dividerColor = Color(0xFFE5E7EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                r.severity,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: r.confidenceColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MetricRow(
          label: 'Detected Condition',
          value: r.disease,
          unit: '',
        ),
        const Divider(color: dividerColor, height: 1),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Confidence',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _barAnim,
                    builder: (_, __) => Text(
                      '${(_barAnim.value * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: r.confidenceColor,
                      ),
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
                    backgroundColor: dividerColor,
                    valueColor: AlwaysStoppedAnimation<Color>(r.confidenceColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (r.top3.isNotEmpty) ...[
          const Divider(color: dividerColor, height: 1),
          const SizedBox(height: 8),
          const Text(
            'Top predictions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...r.top3.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.disease,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textOnLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '${(e.confidence * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        const Divider(color: dividerColor, height: 1),
        const SizedBox(height: 4),
        _MetricRow(
          label: 'Recommendation',
          value: _recommendation(r.disease),
          unit: '',
          valueStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textOnLight,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  String _recommendation(String disease) {
    final d = disease.toLowerCase();
    if (d.contains('healthy')) {
      return 'Plant appears healthy. Continue current care.';
    }
    if (d.contains('rust')) return 'Apply fungicide. Remove infected leaves.';
    if (d.contains('blight')) {
      return 'Improve drainage. Use copper-based fungicide.';
    }
    if (d.contains('mildew')) {
      return 'Increase air circulation. Apply sulfur spray.';
    }
    return 'Consult an agronomist for targeted treatment.';
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
            Icon(
              Icons.eco_rounded,
              size: 48,
              color: scheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'No image analysed yet',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload a plant image and tap Analyse',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.6),
                fontSize: 12,
              ),
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
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Analyzing plant health...',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

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
  const _CardTitle({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textOnLight,
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.unit,
    this.valueStyle,
  });

  final String label;
  final String value;
  final String unit;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
          Flexible(
            child: Text(
              '$value $unit'.trim(),
              textAlign: TextAlign.end,
              style: valueStyle ??
                  const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnLight,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  const _OutlinedBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({
    required this.label,
    this.icon,
    this.loading = false,
    this.onTap,
  });

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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
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
