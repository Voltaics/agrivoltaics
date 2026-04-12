import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Widget plantImagePreview(XFile file) {
  return Image.file(
    File(file.path),
    fit: BoxFit.contain,
    width: double.infinity,
  );
}
