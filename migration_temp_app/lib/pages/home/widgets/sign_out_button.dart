import 'package:flutter/material.dart';
import 'sign_out_dialog.dart';

/// Sign Out Button Widget
/// 
/// A simple button that triggers the sign-out dialog when pressed.
/// Displays a logout icon and integrates with the app's authentication system.
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) => const SignOutDialog(),
              );
            },
            icon: const Icon(Icons.logout),
          ),
        );
      },
    );
  }
}
