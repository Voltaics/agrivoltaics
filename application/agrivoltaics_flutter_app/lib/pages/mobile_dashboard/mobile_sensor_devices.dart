import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PiControlPanel extends StatefulWidget {
  const PiControlPanel({super.key});

  @override
  State<PiControlPanel> createState() => _PiControlPanelState();
}

class _PiControlPanelState extends State<PiControlPanel> {
  bool piOnline = false;
  final String piAddress = 'http://192.168.1.108:5000'; //replace with actual ip

  @override
  void initState() {
    super.initState();
    pingPi();
  }

  Future<void> pingPi() async {
    try {
      final response = await http
          .get(Uri.parse('$piAddress/ping'))
          .timeout(const Duration(seconds: 2));
      setState(() {
        piOnline = response.statusCode == 200;
      });
    } catch (e) {
      setState(() => piOnline = false);
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 20, left: 20, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === TOP ROW: Icon + Title ===
            Row(
              children: [
                const Icon(Icons.memory, size: 24),
                const SizedBox(width: 8),
                Text(
                  "Mobile Sensors",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            const Text(
              "Model: Raspberry Pi 5 8GB",
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              "Camera: MicaSense RedEdge MX",
              style: TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Chip(
                  label: Text(
                    piOnline ? "Online" : "Offline",
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: piOnline ? Colors.green : Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide.none,
                  ),
                  side: BorderSide.none,
                ),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: piOnline ? () => startCapture("single") : null,
                  icon: const Icon(Icons.camera),
                  label: const Text("Single Capture"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: piOnline ? () => startCapture("continuous") : null,
                  icon: const Icon(Icons.loop),
                  label: const Text("Continuous Capture"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
