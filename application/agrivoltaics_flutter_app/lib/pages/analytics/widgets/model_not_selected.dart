import 'package:flutter/material.dart';

class ModelNotSelectedWidget extends StatelessWidget {
  const ModelNotSelectedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No model selected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Pick a model above to render its input form and output section.',
            ),
          ],
        ),
      ),
    );
  }
}
