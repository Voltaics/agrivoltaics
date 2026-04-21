import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// ── Design Tokens ────────────────────────────────────────────────────────────
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

class PestResult {
  final String prediction;
  final double confidence;
  PestResult({required this.prediction, required this.confidence});

  Color get confidenceColor {
    if (confidence > 0.85) return AppColors.successGreen;
    if (confidence > 0.6) return AppColors.warningAmber;
    return AppColors.dangerRed;
  }
}

class PestDetectionPage extends StatefulWidget {
  const PestDetectionPage({super.key});

  @override
  State<PestDetectionPage> createState() => _PestDetectionPageState();
}

class _PestDetectionPageState extends State<PestDetectionPage> with SingleTickerProviderStateMixin {
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

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 90);
    if (image != null) {
      setState(() {
        _selectedXFile = image;
        _result = null;
        _error = null;
      });
    }
  }

  // The core logic to send the image to your Docker container
  Future<void> _analyzeImage() async {
    if (_selectedXFile == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use 10.0.2.2 for Android Emulator, localhost for Web/iOS/Desktop
      String baseUrl = 'https://pest-detection-api-593883469296.us-east4.run.app/pests_predict';
      // if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      //   baseUrl = 'http://10.0.2.2:8080/pests_predict';
      // }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(baseUrl),
      );

      if (kIsWeb) {
        // On Web, read bytes from XFile
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

      if (response.statusCode == 200) {
        setState(() {
          _result = PestResult(
            prediction: jsonDecoded['prediction'],
            confidence: (jsonDecoded['confidence'] as num).toDouble(),
          );
        });
      } else {
        // FastAPI uses 'detail', Flask often uses 'message'. Fallback to raw response if keys are missing.
        final errorMessage = jsonDecoded['error'] ?? jsonDecoded['detail'] ?? jsonDecoded['message'] ?? responseData;
        setState(() => _error = "Server Error (${response.statusCode}): $errorMessage");
      }
    } catch (e) {
      setState(() => _error = "Connection Failed: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _reset() => setState(() {
    _selectedXFile = null;
    _result = null;
    _error = null;
  });

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Row(
        children: [
          _Sidebar(),
          Expanded(
            child: Column(
              children: [
                _TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pest Detection Scan',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        const Text('Upload crop images to identify pests', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(height: 24),
                        LayoutBuilder(builder: (context, constraints) {
                          if (constraints.maxWidth > 700) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: _buildImageCard()),
                                const SizedBox(width: 20),
                                Expanded(flex: 5, child: _buildResultCard()),
                              ],
                            );
                          }
                          return Column(children: [_buildImageCard(), const SizedBox(height: 20), _buildResultCard()]);
                        }),
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

  Widget _buildImageCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.camera_alt_rounded, label: 'Image Input'),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _pickImage(ImageSource.gallery),
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                color: _selectedXFile == null ? AppColors.scaffoldBg : Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withOpacity(0.2)),
              ),
              clipBehavior: Clip.hardEdge,
              child: _selectedXFile == null
                  ? const Center(child: Icon(Icons.upload_file_rounded, size: 48, color: AppColors.accent))
                  : (kIsWeb
                      ? Image.network(_selectedXFile!.path, fit: BoxFit.contain, width: double.infinity)
                      : Image.file(File(_selectedXFile!.path), fit: BoxFit.contain, width: double.infinity)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _OutlinedBtn(icon: Icons.photo_library, label: 'Gallery', onTap: () => _pickImage(ImageSource.gallery))),
              const SizedBox(width: 12),
              Expanded(child: _OutlinedBtn(icon: Icons.camera_alt, label: 'Camera', onTap: () => _pickImage(ImageSource.camera))),
              if (_selectedXFile != null) ...[
                const SizedBox(width: 12),
                Expanded(child: _OutlinedBtn(icon: Icons.refresh, label: 'Reset', onTap: _reset, color: AppColors.dangerRed)),
              ]
            ],
          ),
          if (_selectedXFile != null) ...[
            const SizedBox(height: 16),
            _PrimaryBtn(
              label: _isLoading ? 'Analyzing...' : 'Analyze Image',
              icon: Icons.biotech_rounded,
              loading: _isLoading,
              onTap: _isLoading ? null : _analyzeImage,
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(icon: Icons.analytics_rounded, label: 'Analysis Results'),
          const SizedBox(height: 16),
          if (_isLoading)
            Center(child: ScaleTransition(scale: _pulseAnim, child: const CircularProgressIndicator(color: AppColors.navyMid)))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.dangerRed))
          else if (_result != null)
            _ResultDisplay(result: _result!)
          else
            const Center(child: Text('No image analyzed yet', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}

class _ResultDisplay extends StatelessWidget {
  final PestResult result;
  const _ResultDisplay({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: result.confidenceColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(result.prediction, style: TextStyle(fontWeight: FontWeight.bold, color: result.confidenceColor)),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Confidence', style: TextStyle(color: AppColors.textSecondary)),
            Text('${(result.confidence * 100).toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: result.confidenceColor)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: result.confidence, backgroundColor: AppColors.divider, color: result.confidenceColor, minHeight: 8),
      ],
    );
  }
}

// ── UI Components (Consistent with docker_app/backend/plant_disease_detection.dart) ────────────────
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
    return Row(children: [Icon(icon, size: 16, color: AppColors.navyMid), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))]);
  }
}

class _Sidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.navyDark,
      child: Column(
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Row(children: [Icon(Icons.bolt, color: Colors.white), SizedBox(width: 8), Text('Vinovoltaics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])),
          _SidebarItem(icon: Icons.location_on, label: 'Vineyard', active: false),
          _SidebarItem(icon: Icons.biotech_rounded, label: 'Pest Scan', active: true),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _SidebarItem({required this.icon, required this.label, required this.active});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: active ? AppColors.navyLight : Colors.transparent, borderRadius: BorderRadius.circular(6)),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: active ? Colors.white : Colors.white54, size: 18),
        title: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 13)),
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
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.divider))),
      child: const Row(children: [Text('Vineyard', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)), Icon(Icons.chevron_right, size: 16), Text('Pest Scan', style: TextStyle(fontWeight: FontWeight.bold))]),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _OutlinedBtn({required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.navyMid;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c, fontSize: 12)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: c.withOpacity(0.4)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;
  const _PrimaryBtn({required this.label, required this.icon, required this.loading, this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyMid, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }
}