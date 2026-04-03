import 'package:agrivoltaics_flutter_app/app_colors.dart';
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

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _errorMessage = null;
    });

    if (kIsWeb) {
      try {
        UserCredential userCredential = await signInWithGoogleWeb();

        if (!mounted) return;

        if (authorizeUser(userCredential)) {
          await _userService.createOrUpdateUser();
          final appUser = await _userService.getCurrentUser();

          if (!mounted) return;

          if (appUser != null) {
            final appState = Provider.of<AppState>(context, listen: false);
            appState.setCurrentUser(appUser);
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const OrganizationSelectionPage(),
            ),
          );
        } else {
          setState(() {
            _errorMessage =
                'Your account is not on the email whitelist. Contact an administrator to request access.';
          });
          await signOut();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'An error occurred during sign in. Please try again.';
        });
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OrganizationSelectionPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Background gradient ─────────────────────────────────────
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.background, AppColors.backgroundGradientEnd],
              ),
            ),
          ),

          // ── Decorative geometric circles ────────────────────────────
          const Positioned(
            top: -80,
            right: -80,
            child: _DecorativeCircle(size: 380, opacity: 0.06),
          ),
          const Positioned(
            top: 40,
            right: 40,
            child: _DecorativeCircle(size: 240, opacity: 0.04),
          ),
          Positioned(
            bottom: 260,
            left: -100,
            child: _DecorativeCircle(
              size: 320,
              opacity: 0.0,
              borderColor: AppColors.primary.withValues(alpha: 0.14),
            ),
          ),

          // ── Content ─────────────────────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape = constraints.maxWidth > constraints.maxHeight;
                final isDesktop = constraints.maxWidth >= 1100;
                final isShortHeight = constraints.maxHeight < 760;

                if (isLandscape && !isDesktop) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Center(
                            child: _buildHeroSection(isShortHeight: isShortHeight),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: constraints.maxWidth * 0.45,
                            height: double.infinity,
                            child: _buildSignInCard(
                              isShortHeight: isShortHeight,
                              landscapeAttached: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (isDesktop) {
                  return Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: Center(
                            child: _buildHeroSection(isShortHeight: isShortHeight),
                          ),
                        ),
                      ),
                      _buildSignInCard(
                        isShortHeight: isShortHeight,
                        minHeight: isShortHeight ? 300 : 340,
                      ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                          child: _buildHeroSection(isShortHeight: isShortHeight),
                        ),
                        _buildSignInCard(isShortHeight: isShortHeight),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection({required bool isShortHeight}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: isShortHeight ? 16 : 24),
        Container(
          width: isShortHeight ? 72 : 84,
          height: isShortHeight ? 72 : 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.eco,
            color: AppColors.textPrimary,
            size: isShortHeight ? 36 : 42,
          ),
        ),
        SizedBox(height: isShortHeight ? 16 : 24),
        const Text(
          'Vinovoltaics',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Precision insights for modern farms',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isShortHeight ? 24 : 52),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            _FeatureChip(
              icon: Icons.eco,
              label: 'Crop Health',
              iconColor: AppColors.farmGreen,
            ),
            _FeatureChip(
              icon: Icons.agriculture,
              label: 'Farm Data',
              iconColor: AppColors.amber,
            ),
            _FeatureChip(
              icon: Icons.bar_chart_rounded,
              label: 'Analytics',
              iconColor: AppColors.primaryLight,
            ),
          ],
        ),
        SizedBox(height: isShortHeight ? 18 : 26),
      ],
    );
  }

  Widget _buildSignInCard({
    required bool isShortHeight,
    bool landscapeAttached = false,
    double? minHeight,
  }) {
    return Container(
      width: double.infinity,
      constraints:
          minHeight != null ? BoxConstraints(minHeight: minHeight) : null,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: landscapeAttached
            ? const BorderRadius.only(
                topLeft: Radius.circular(36),
                bottomLeft: Radius.circular(36),
              )
            : const BorderRadius.vertical(
                top: Radius.circular(36),
              ),
        boxShadow: landscapeAttached
            ? const [
                BoxShadow(
                  color: Color(0x2A000000),
                  blurRadius: 16,
                  offset: Offset(-4, 0),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.fromLTRB(
        32,
        landscapeAttached ? (isShortHeight ? 28 : 36) : (isShortHeight ? 24 : 36),
        32,
        landscapeAttached ? (isShortHeight ? 24 : 32) : (isShortHeight ? 28 : 48),
      ),
      child: SingleChildScrollView(
        physics: landscapeAttached
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              landscapeAttached ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.background,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to monitor your farms and track insights.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 28),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.errorBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.errorDark, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.errorDark,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: SignInButton(
                Buttons.Google,
                onPressed: _handleGoogleSignIn,
                padding: const EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ───────────────────────────────────────────────────────

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final double opacity;
  final Color? borderColor;

  const _DecorativeCircle({
    required this.size,
    required this.opacity,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? AppColors.textPrimary.withValues(alpha: opacity),
          width: 1.2,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}