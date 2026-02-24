import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
import 'capture_detail_tabs.dart';

class CaptureDetailPage extends StatelessWidget {
  final DocumentSnapshot document;

  const CaptureDetailPage({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final data = document.data() as Map<String, dynamic>;
    // Extract URLs from the 'url' list
    final List<String> imageUrls = List<String>.from(data['url'] ?? []);
    // Provide defaults if some images are missing
    final rawUrl = imageUrls.isNotEmpty ? imageUrls[0] : '';
    final ndviUrl = imageUrls.length > 1 ? imageUrls[1] : '';
    final ndreUrl = imageUrls.length > 2 ? imageUrls[2] : '';
    final overlayUrl = imageUrls.length > 3 ? imageUrls[3] : '';
    final heatmapUrl = imageUrls.length > 4 ? imageUrls[4] : '';

    // final timestamp = DateTime.fromMillisecondsSinceEpoch(
    //   data['timestamp'].seconds * 1000,
    // ).toLocal();

    // final dateStr = "${timestamp.month}/${timestamp.day}/${timestamp.year}";
    // final timeStr = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          // Top card with capture details. commented out for now to reduce repeating the same thing again. may adjust for futures
          /*
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date & Time row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.access_time, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Disease status chip
                  Chip(
                    label: Text(
                      data['detected_disease'] == true
                          ? 'Disease Detected'
                          : 'No Disease Detected',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    backgroundColor: data['detected_disease'] == true ? AppColors.error : AppColors.success,
                  ),
                  const SizedBox(height: 16),
                  // AI Analysis summary
                  /*Row(
                    children: [
                      const Icon(Icons.insights, size: 24),
                      const SizedBox(width: 6),
                      const Text(
                        "AI Analysis: ",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          data['analysis_summary'] ?? "",
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),*/
                ],
              ),
            ),
          ),*/
          const SizedBox(height: 16),
          // Tabbed image viewer: displays Raw, NDVI, NDRE, Overlay, and Heatmap images.
          CaptureDetailDualEqualView(
            rawUrl: rawUrl,
            ndviUrl: ndviUrl,
            ndreUrl: ndreUrl,
            overlayUrl: overlayUrl,
            heatmapUrl: heatmapUrl,
          ),
        ],
      ),
    );
  }
}
