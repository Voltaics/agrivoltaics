import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Widget plantImagePreview(XFile file) {
  return Image.network(
    file.path,
    fit: BoxFit.contain,
    width: double.infinity,
  );
}
