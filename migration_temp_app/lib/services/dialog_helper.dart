import 'package:flutter/material.dart';

/// Service for standardizing and simplifying dialog operations across the application.
/// Reduces boilerplate code and ensures consistent UX for all dialogs.
class DialogHelper {
  // Singleton instance
  static final DialogHelper _instance = DialogHelper._internal();

  factory DialogHelper() {
    return _instance;
  }

  DialogHelper._internal();

  /// Show a simple confirmation dialog
  /// Returns true if confirmed, false if cancelled
  Future<bool?> showConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    String confirmButtonText = 'Confirm',
    String cancelButtonText = 'Cancel',
    Color confirmButtonColor = const Color(0xFF2196F3),
    Color cancelButtonColor = Colors.grey,
    bool dangerous = false,
  }) {
    final confirmColor = dangerous ? Colors.red : confirmButtonColor;

    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: cancelButtonColor),
            child: Text(cancelButtonText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmButtonText),
          ),
        ],
      ),
    );
  }

  /// Show an error dialog
  Future<void> showError(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show a success dialog
  Future<void> showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show an info dialog
  Future<void> showInfo(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show a warning dialog
  Future<void> showWarning(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Show a simple text input dialog
  /// Returns the entered text or null if cancelled
  Future<String?> showTextInput(
    BuildContext context, {
    required String title,
    required String hintText,
    String initialValue = '',
    String submitButtonText = 'Submit',
    String cancelButtonText = 'Cancel',
    int maxLength = 255,
    int minLength = 1,
    String? Function(String?)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? errorText;

    return showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLength: maxLength,
                  decoration: InputDecoration(
                    hintText: hintText,
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    setState(() {
                      errorText = null;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(cancelButtonText),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text;

                if (value.isEmpty && minLength > 0) {
                  setState(() {
                    errorText = 'This field is required';
                  });
                  return;
                }

                if (value.length < minLength) {
                  setState(() {
                    errorText = 'Must be at least $minLength characters';
                  });
                  return;
                }

                if (validator != null) {
                  final error = validator(value);
                  if (error != null) {
                    setState(() {
                      errorText = error;
                    });
                    return;
                  }
                }

                Navigator.pop(context, value);
              },
              child: Text(submitButtonText),
            ),
          ],
        ),
      ),
    );
  }

  /// Show a custom dialog with a builder function
  Future<T?> showCustom<T>(
    BuildContext context, {
    required Widget Function(BuildContext context) builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T?>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  /// Show a loading dialog with message
  Future<void> showLoading(
    BuildContext context, {
    required String message,
    bool dismissible = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: dismissible,
      builder: (context) => PopScope(
        canPop: dismissible,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show a bottom sheet with custom content
  Future<T?> showBottomSheet<T>(
    BuildContext context, {
    required Widget Function(BuildContext context) builder,
    bool dismissible = true,
    bool isScrollControlled = false,
  }) {
    return showModalBottomSheet<T?>(
      context: context,
      isDismissible: dismissible,
      isScrollControlled: isScrollControlled,
      builder: builder,
    );
  }

  /// Show a snackbar message (non-blocking)
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    BuildContext context, {
    required String message,
    int durationSeconds = 4,
    SnackBarAction? action,
    Color? backgroundColor,
  }) {
    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: durationSeconds),
        action: action,
        backgroundColor: backgroundColor,
      ),
    );
  }

  /// Show a success snackbar
  void showSuccessSnackBar(
    BuildContext context, {
    required String message,
    int durationSeconds = 4,
  }) {
    showSnackBar(
      context,
      message: message,
      durationSeconds: durationSeconds,
      backgroundColor: Colors.green,
    );
  }

  /// Show an error snackbar
  void showErrorSnackBar(
    BuildContext context, {
    required String message,
    int durationSeconds = 4,
  }) {
    showSnackBar(
      context,
      message: message,
      durationSeconds: durationSeconds,
      backgroundColor: Colors.red,
    );
  }

  /// Show a warning snackbar
  void showWarningSnackBar(
    BuildContext context, {
    required String message,
    int durationSeconds = 4,
  }) {
    showSnackBar(
      context,
      message: message,
      durationSeconds: durationSeconds,
      backgroundColor: Colors.orange,
    );
  }

  /// Close any open dialogs
  void closeDialog(BuildContext context) {
    Navigator.of(context).pop();
  }

  /// Check if a dialog is currently open
  bool isDialogOpen(BuildContext context) {
    return Navigator.of(context).canPop();
  }
}
