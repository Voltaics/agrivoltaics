import 'package:agrivoltaics_flutter_app/auth.dart';
import 'package:agrivoltaics_flutter_app/services/user_service.dart';
import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'organization_selection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_signin_button/flutter_signin_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final UserService _userService = UserService();
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
            // mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const Spacer(flex: 2),
              const Text(
                'Vinovoltaics',
                style: TextStyle(
                  fontSize: 50
                ),
              ),
              const Spacer(),
              if (_errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              SignInButton(
                Buttons.Google,
                // child: const Text('Login'),
                onPressed: () async {
                  setState(() {
                    _errorMessage = null;
                  });

                  if (kIsWeb) {
                    try {
                      UserCredential userCredential = await signInWithGoogleWeb();
                      
                      if (!mounted) return;
                      
                      if (authorizeUser(userCredential)) {
                        // User is authorized, create/update user document
                        await _userService.createOrUpdateUser();
                        
                        // Get the user document and store in AppState
                        final appUser = await _userService.getCurrentUser();
                        
                        if (!mounted) return;
                        
                        if (appUser != null) {
                          final appState = Provider.of<AppState>(context, listen: false);
                          appState.setCurrentUser(appUser);
                        }
                        
                        // Navigate to organization selection
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const OrganizationSelectionPage()
                          )
                        );
                      } else {
                        // User is not authorized
                        setState(() {
                          _errorMessage = 'The user is not on the email whitelist. You need to add it to the list in the GitHub Actions Deployment Environment Variables.';
                        });
                        // Sign out the unauthorized user
                        await signOut();
                      }
                    } catch (e) {
                      if (!mounted) return;
                      setState(() {
                        _errorMessage = 'An error occurred during sign in. Please try again.';
                      });
                    }
                  } else {
                    // Future<UserCredential> userPromise = signInWithGoogleMobile();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const OrganizationSelectionPage()
                      )
                    );
                  }
                },
              ),
              const Spacer(flex: 2),
            ],
          ),
      ),
    );
  }
}