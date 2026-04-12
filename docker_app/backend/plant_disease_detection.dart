import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const PlantDiseaseApp());
}

class PlantDiseaseApp extends StatelessWidget {
  const PlantDiseaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Disease Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.navyMid),
        useMaterial3: true,
      ),
      home: const PlantDiseaseScreen(),
    );
  }
}

// ── Vinovoltaics Design Tokens ──────────────────────────────────────────────
class AppColors {
  static const navyDark = Color(0xFF1A237E);
  static const navyMid = Color(0xFF283593);
  static const navyLight = Color(0xFF3949AB);
  static const accent = Color(0xFF5C6BC0);
  static const scaffoldBg = Color(0xFFF0F2FF);
  static const cardBg = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6B7280);
  static const divider = Color(0xFFE5E7EB);
  static const successGreen = Color(0xFF10B981);
  static const warningAmber = Color(0xFFF59E0B);
  static const dangerRed = Color(0xFFEF4444);
}

// ── Model Response ────────────────────────────────────────────────────────────
class DiseaseResult {
  final String disease;
  final double confidence;
  final String severity; // derived

  DiseaseResult({required this.disease, required this.confidence})
    : severity = confidence > 0.85
          ? 'High Confidence'
          : confidence > 0.6
          ? 'Moderate Confidence'
          : 'Low Confidence';

  Color get confidenceColor {
    if (confidence > 0.85) return AppColors.successGreen;
    if (confidence > 0.6) return AppColors.warningAmber;
    return AppColors.dangerRed;
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────
class PlantDiseaseScreen extends StatefulWidget {
  const PlantDiseaseScreen({super.key});

  @override
  State<PlantDiseaseScreen> createState() => _PlantDiseaseScreenState();
}

class _PlantDiseaseScreenState extends State<PlantDiseaseScreen>
    with SingleTickerProviderStateMixin {
  XFile? _selectedImage;
  DiseaseResult? _result;
  bool _isLoading = false;
  String? _error;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── Replace with your actual API endpoint ──
  static const String _apiUrl = 'http://localhost:8000/predict';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Image Picker ──────────────────────────────────────────────────────────
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

  // ── API Call ──────────────────────────────────────────────────────────────
  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
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
        setState(() {
          _result = DiseaseResult(
            disease: json['disease'] as String,
            confidence: (json['confidence'] as num).toDouble(),
          );
        });
      } else {
        setState(() => _error = 'Server error (${response.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Failed to connect to analysis server.\n$e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _reset() => setState(() {
    _selectedImage = null;
    _result = null;
    _error = null;
  });

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Row(
        children: [
          _Sidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          title: 'Plant Disease Detection',
                          subtitle:
                              'Upload or capture a plant image to diagnose',
                        ),
                        const SizedBox(height: 24),
                        _buildMainGrid(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _ImagePanel()),
              const SizedBox(width: 20),
              Expanded(flex: 5, child: _ResultsPanel()),
            ],
          );
        }
        return Column(
          children: [
            _ImagePanel(),
            const SizedBox(height: 20),
            _ResultsPanel(),
          ],
        );
      },
    );
  }

  // ── Image Panel ───────────────────────────────────────────────────────────
  Widget _ImagePanel() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.camera_alt_rounded,
            label: 'Image Input',
          ),
          const SizedBox(height: 16),

          // Preview or drop zone
          GestureDetector(
            onTap: () => _pickImage(ImageSource.gallery),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 280,
              decoration: BoxDecoration(
                color: _selectedImage == null
                    ? AppColors.scaffoldBg
                    : Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedImage == null
                      ? AppColors.accent.withOpacity(0.35)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedImage == null
                  ? _DropZoneContent()
                  : _ImagePreview(file: _selectedImage!),
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
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
                    color: AppColors.dangerRed,
                  ),
                ),
            ],
          ),

          if (_selectedImage != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: _PrimaryBtn(
                label: _isLoading ? 'Analysing…' : 'Analyse Plant',
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

  // ── Results Panel ─────────────────────────────────────────────────────────
  Widget _ResultsPanel() {
    return _Card(
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
            _EmptyResultState(),
        ],
      ),
    );
  }
}

// ── Image Preview ─────────────────────────────────────────────────────────────
class _ImagePreview extends StatelessWidget {
  final XFile file;
  const _ImagePreview({required this.file});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        file.path,
        fit: BoxFit.contain,
        width: double.infinity,
      );
    }
    return Image.file(
      File(file.path),
      fit: BoxFit.contain,
      width: double.infinity,
    );
  }
}

// ── Drop Zone ─────────────────────────────────────────────────────────────────
class _DropZoneContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(32),
          ),
          child: const Icon(
            Icons.upload_file_rounded,
            size: 32,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Click to upload a plant image',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'JPG, PNG, WEBP supported',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Result Content ─────────────────────────────────────────────────────────────
class _ResultContent extends StatefulWidget {
  final DiseaseResult result;
  const _ResultContent({required this.result});

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: r.confidenceColor.withOpacity(0.12),
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

        // Metric rows matching Vinovoltaics sensor style
        _MetricRow(label: 'Detected Condition', value: r.disease, unit: ''),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 4),

        // Confidence with animated bar
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
                      color: AppColors.textSecondary,
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
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation(r.confidenceColor),
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 4),
        _MetricRow(
          label: 'Recommendation',
          value: _recommendation(r.disease),
          unit: '',
          valueStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  String _recommendation(String disease) {
    final d = disease.toLowerCase();
    if (d.contains('healthy'))
      return 'Plant appears healthy. Continue current care.';
    if (d.contains('rust')) return 'Apply fungicide. Remove infected leaves.';
    if (d.contains('blight'))
      return 'Improve drainage. Use copper-based fungicide.';
    if (d.contains('mildew'))
      return 'Increase air circulation. Apply sulfur spray.';
    return 'Consult an agronomist for targeted treatment.';
  }
}

// ── Empty / Loading / Error States ────────────────────────────────────────────
class _EmptyResultState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.eco_rounded,
              size: 48,
              color: AppColors.accent.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No image analysed yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload a plant image and tap Analyse',
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.6),
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
  final Animation<double> animation;
  const _LoadingState({required this.animation});

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: animation,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.navyMid,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Analysing plant health…',
                style: TextStyle(
                  color: AppColors.textSecondary,
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
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.dangerRed.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.dangerRed,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.dangerRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared UI Components ──────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.navyDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Vinovoltaics',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // Org switcher
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.navyMid,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Center(
                    child: Text(
                      'U',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'UC Vinovoltaics',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Switch organization',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _SidebarSection(
            title: 'Sites',
            items: const [
              _SidebarItem(
                icon: Icons.location_on_rounded,
                label: 'Vineyard',
                active: false,
              ),
              _SidebarItem(
                icon: Icons.location_on_outlined,
                label: 'Test Site 1',
                active: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SidebarSection(
            title: 'Tools',
            items: const [
              _SidebarItem(
                icon: Icons.biotech_rounded,
                label: 'Disease Scan',
                active: true,
              ),
              _SidebarItem(
                icon: Icons.sensors_rounded,
                label: 'Sensors',
                active: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  final String title;
  final List<_SidebarItem> items;
  const _SidebarSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...items,
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? AppColors.navyLight : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: active ? Colors.white : Colors.white54,
          size: 18,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // Breadcrumb
          const Text(
            'Vineyard',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const Text(
            'Disease Scan',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.settings_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
  final IconData icon;
  final String label;
  const _CardTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.navyMid),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final TextStyle? valueStyle;
  const _MetricRow({
    required this.label,
    required this.value,
    required this.unit,
    this.valueStyle,
  });

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
              color: AppColors.textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              '$value $unit'.trim(),
              textAlign: TextAlign.end,
              style:
                  valueStyle ??
                  const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _OutlinedBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.navyMid;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;
  const _PrimaryBtn({
    required this.label,
    this.icon,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: AppColors.navyMid,
        disabledBackgroundColor: AppColors.navyMid.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}
