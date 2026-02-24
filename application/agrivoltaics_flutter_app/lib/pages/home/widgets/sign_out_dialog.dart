import 'package:flutter/material.dart';
import '../../../pages/login.dart';
import '../../../auth.dart';
import '../../../app_state.dart';
import 'package:provider/provider.dart';

/// Sign Out Dialog Widget
/// 
/// A confirmation dialog that prompts the user to confirm their sign-out action.
/// Handles clearing app state, Firebase sign-out, and navigation to login page.
class SignOutDialog extends StatelessWidget {
  const SignOutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'Cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            // Clear user state
            final appState = Provider.of<AppState>(context, listen: false);
            appState.clearCurrentUser();

            // Sign out from Firebase
            await signOut();

            if (!context.mounted) return;

            // Navigate to login
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
          },
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
