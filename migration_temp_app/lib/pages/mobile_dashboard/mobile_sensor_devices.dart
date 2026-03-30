import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PiControlPanel extends StatefulWidget {
  const PiControlPanel({super.key});

  @override
  State<PiControlPanel> createState() => _PiControlPanelState();
}

class _PiControlPanelState extends State<PiControlPanel> {
  bool piOnline = false;
  bool expanded = false;
  bool _isDisposed = false;
  final String piAddress = 'http://192.168.1.108:5000'; //replace with actual ip

  @override
  void initState() {
    super.initState();
    pingPi();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> pingPi() async {
    try {
      final response = await http
          .get(Uri.parse('$piAddress/ping'))
          .timeout(const Duration(seconds: 2));
      
      if (!_isDisposed && mounted) {
        setState(() {
          piOnline = response.statusCode == 200;
        });
      }
    } catch (e) {
      if (!_isDisposed && mounted) {
        setState(() => piOnline = false);
      }
    }
  }

  Future<void> startCapture(String mode) async {
    final url = Uri.parse('$piAddress/start-capture?mode=$mode');

    try {
      final response = await http
          .post(url)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture started ($mode)'))
        );
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start capture: $e'))
      );
    }
  }

  Widget _ExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hardware Details Section
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Model: Raspberry Pi 5 8GB",
                style: TextStyle(fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                "Camera: MicaSense RedEdge MX",
                style: TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
        const Divider(),
        const SizedBox(height: 12),

        // Capture Buttons (single / continuous) - disabled when Pi offline
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: piOnline ? () => startCapture("single") : null,
                icon: const Icon(Icons.camera),
                label: const Text("Single Capture"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: piOnline ? () => startCapture("continuous") : null,
                icon: const Icon(Icons.loop),
                label: const Text("Continuous Capture"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isNarrow = screenWidth < 714; // collapse only on narrow screens
    final isWideScreen = MediaQuery.of(context).size.width >= 1280 || screenHeight < screenWidth;

    if (!isWideScreen) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        
        child: Column(
          children: [
            // ===== HEADER (ALWAYS VISIBLE) =====
            InkWell(
              onTap: isNarrow ? () => setState(() => expanded = !expanded) : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.memory, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      "Mobile Sensors",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(
                        piOnline ? "Online" : "Offline",
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: piOnline ? Colors.green : Colors.red,
                    ),

                    if (isNarrow) const SizedBox(width: 8),
                    if (isNarrow)
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                  ],
                ),
              ),
            ),

            // ===== EXPANDABLE CONTENT =====
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: (isNarrow ? expanded : true)
                ? Padding(
                  padding:
                    const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _ExpandedContent(),
                  )
                : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}