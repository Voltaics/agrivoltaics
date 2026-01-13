import 'package:agrivoltaics_flutter_app/pages/mobile_dashboard/mobile_sensor_devices.dart';
import 'package:agrivoltaics_flutter_app/pages/mobile_dashboard/capture_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';


class MobileDashboardPage extends StatefulWidget {
  const MobileDashboardPage({super.key});

  @override
  State<MobileDashboardPage> createState() => _MobileDashboardPageState();
}

class _MobileDashboardPageState extends State<MobileDashboardPage> {
  bool showAllCaptures = true;
  DocumentSnapshot? selectedCapture;

   void selectCapture(DocumentSnapshot doc) {
    setState(() => selectedCapture = doc);
  }

  void goBackToGrid() {
    setState(() => selectedCapture = null);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 36, bottom: 16, right: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Title
                  Text(
                    showAllCaptures
                        ? (selectedCapture != null
                            ? 'Capture Details'
                            : 'All Captures')
                        : (selectedCapture != null
                            ? 'Capture Details'
                            : 'Flagged Captures'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // If no capture selected, show toggle button
                  if (selectedCapture == null) 
                    ElevatedButton(
                      onPressed: () {
                        setState(() => showAllCaptures = !showAllCaptures);
                      },
                      child: Text(
                        showAllCaptures
                            ? 'Show Flagged Only'
                            : 'Show All',
                      ),
                    )
                  else 
                    // If capture is selected, show back arrow
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: goBackToGrid,
                    ),
                ],
              ),
            ),
            Expanded(
              child: selectedCapture != null
                  ? CaptureDetailPage(document: selectedCapture!)
                  : MobileDashboard(
                      showAllCaptures: showAllCaptures,
                      onCaptureSelected: selectCapture,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class MobileDashboard extends StatelessWidget {
  final bool showAllCaptures;
  final void Function(DocumentSnapshot doc) onCaptureSelected;

  const MobileDashboard({super.key, 
    required this.showAllCaptures,
    required this.onCaptureSelected,
  });

  @override
  Widget build(BuildContext context) {

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWideScreen = MediaQuery.of(context).size.width >= 1280 || screenHeight < screenWidth;

    final stream = showAllCaptures
        ? FirebaseFirestore.instance
            .collection('captures')
            .orderBy('timestamp', descending: true)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('captures')
            .where('detected_disease', isEqualTo: true)
            .orderBy('timestamp', descending: true)
            .snapshots();

    if (isWideScreen) {
      return Row(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No captures found'));
                }

                final captures = snapshot.data!.docs;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: ListView.builder(
                    itemCount: captures.length,
                    itemBuilder: (context, index) {
                      final doc = captures[index];
                      final data = doc.data() as Map<String, dynamic>;

                      // Extract timestamp
                      final timestamp = DateTime.fromMillisecondsSinceEpoch(
                        data['timestamp'].seconds * 1000,
                      ).toLocal();

                      // Format date & time
                      final dateStr =
                          "${timestamp.month}/${timestamp.day}/${timestamp.year}";
                      final timeStr =
                          "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";

                      // Build image paths
                      final urlData = data['url'];
                      final imagePaths = urlData == null
                          ? []
                          : (urlData is List
                              ? List<String>.from(urlData)
                              : [urlData]);

                      final bool isDisease = data['detected_disease'] == true;

                      return Card(
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
                              // === TOP ROW: Date/Time (left), View Button (right) ===
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Date & Time
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

                                  // View Button
                                  ElevatedButton.icon(
                                    onPressed: () => onCaptureSelected(doc),
                                    icon: const Icon(Icons.visibility),
                                    label: const Text("View"),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      textStyle: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // === DISEASE STATUS CHIP ===
                              Chip(
                                label: Text(
                                  isDisease
                                      ? 'Disease Detected'
                                      : 'No Disease Detected',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                backgroundColor:
                                    isDisease ? Colors.red : Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide.none,
                                ),
                                side: BorderSide.none,
                              ),

                              const SizedBox(height: 24),

                              // === IMAGES ROW ===
                              SizedBox(
                                height: 100,
                                child: imagePaths.isEmpty
                                    ? const Center(child: Text('No images'))
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: imagePaths.length,
                                        itemBuilder: (context, imgIndex) {
                                          final path = imagePaths[imgIndex];
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(right: 12),
                                            child: FutureBuilder(
                                              future: FirebaseStorage.instance
                                                  .ref(path)
                                                  .getDownloadURL(),
                                              builder: (context, imgSnapshot) {
                                                if (!imgSnapshot.hasData) {
                                                  return const SizedBox(
                                                    width: 100,
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.network(
                                                    imgSnapshot.data!,
                                                    width: 100,
                                                    height: 100,
                                                    fit: BoxFit.cover,
                                                  ),
                                                );
                                              },
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 24, top: 12),
            child: Container(
              width: 419,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[100],
              child: const PiControlPanel(
                // piOnline: true, // TODO: replace with actual ping logic
                // onStartCapture: () {
                //   // TODO: add capture trigger logic
                // },
              ),
            ),
          ),
        ],
      );
    }
    
    if (!isWideScreen){
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 24, top: 12),
            child: Container(
              width: 419,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[100],
              child: const PiControlPanel(
                // piOnline: true, // TODO: replace with actual ping logic
                // onStartCapture: () {
                //   // TODO: add capture trigger logic
                // },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No captures found'));
                }

                final captures = snapshot.data!.docs;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: ListView.builder(
                    itemCount: captures.length,
                    itemBuilder: (context, index) {
                      final doc = captures[index];
                      final data = doc.data() as Map<String, dynamic>;

                      // Extract timestamp
                      final timestamp = DateTime.fromMillisecondsSinceEpoch(
                        data['timestamp'].seconds * 1000,
                      ).toLocal();

                      // Format date & time
                      final dateStr =
                          "${timestamp.month}/${timestamp.day}/${timestamp.year}";
                      final timeStr =
                          "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";

                      // Build image paths
                      final urlData = data['url'];
                      final imagePaths = urlData == null
                          ? []
                          : (urlData is List
                              ? List<String>.from(urlData)
                              : [urlData]);

                      final bool isDisease = data['detected_disease'] == true;

                      return Card(
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
                              // === TOP ROW: Date/Time (left), View Button (right) ===
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Date & Time
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

                                  // View Button
                                  ElevatedButton.icon(
                                    onPressed: () => onCaptureSelected(doc),
                                    icon: const Icon(Icons.visibility),
                                    label: const Text("View"),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      textStyle: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // === DISEASE STATUS CHIP ===
                              Chip(
                                label: Text(
                                  isDisease
                                      ? 'Disease Detected'
                                      : 'No Disease Detected',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                backgroundColor:
                                    isDisease ? Colors.red : Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide.none,
                                ),
                                side: BorderSide.none,
                              ),

                              const SizedBox(height: 24),

                              // === IMAGES ROW ===
                              SizedBox(
                                height: 100,
                                child: imagePaths.isEmpty
                                    ? const Center(child: Text('No images'))
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: imagePaths.length,
                                        itemBuilder: (context, imgIndex) {
                                          final path = imagePaths[imgIndex];
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(right: 12),
                                            child: FutureBuilder(
                                              future: FirebaseStorage.instance
                                                  .ref(path)
                                                  .getDownloadURL(),
                                              builder: (context, imgSnapshot) {
                                                if (!imgSnapshot.hasData) {
                                                  return const SizedBox(
                                                    width: 100,
                                                    child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.network(
                                                    imgSnapshot.data!,
                                                    width: 100,
                                                    height: 100,
                                                    fit: BoxFit.cover,
                                                  ),
                                                );
                                              },
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return const Placeholder();
  }
}
