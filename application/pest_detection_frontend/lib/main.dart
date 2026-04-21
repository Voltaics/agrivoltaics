import 'package:flutter/material.dart';
import 'pest_detection_page.dart'; // Import your new page

void main() => runApp(const PestDetectionApp());

class PestDetectionApp extends StatelessWidget {
  const PestDetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pest Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF283593)),
        useMaterial3: true,
      ),
      home: const PestDetectionPage(),
    );
  }
}