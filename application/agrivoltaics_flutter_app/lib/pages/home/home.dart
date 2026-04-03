import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'notifications.dart';
import '../stationary_dashboard/stationary_dashboard.dart';
import '../mobile_dashboard/mobile_dashboard.dart';
import '../historical_dashboard/historical_dashboard.dart';
import '../alerts/alerts_page.dart';
import '../analytics/analytics_dashboard.dart';
import 'widgets/organization_menu_sheet.dart';
import 'widgets/organization_selector.dart';
import 'widgets/sign_out_dialog.dart';
import '../../app_state.dart';
import '../../services/fcm_service.dart';
import '../../responsive/app_viewport.dart';

class HomeState extends StatefulWidget {
  const HomeState({
    super.key
  });

  @override
  State<HomeState> createState() => HomePage();
}

/*

Home Page
- All navigations redirect back here

*/
class HomePage extends State<HomeState> {

  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    StationaryDashboardPage(),  // Stationary Sensors
    HistoricalDashboardPage(),        // Historical Trends
    MobileDashboardPage(),            // Mobile Sensors
    AnalyticsDashboardPage(),         // Analytics
    AlertsPage(),                     // Alert Rules
  ];

  // FCM token status for in-app banner
  bool _fcmTokenInvalid = false;
  final FcmService _fcmService = FcmService();

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showOrganizationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const OrganizationMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportInfo = AppViewportInfo.fromMediaQuery(MediaQuery.of(context));
     return Scaffold(
      // 1) No AppBar here—removed entirely
      // 2) Row that holds [ Nav Rail (left) | Main Content (right) ]
      body: Column(
        children: [
          // FCM token invalidated banner
          if (_fcmTokenInvalid)
            Material(
              color: AppColors.errorLight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_off,
                        color: AppColors.errorDark),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Your notification token has been invalidated. '
                        'Please re-enable notifications to continue receiving alerts.',
                        style: TextStyle(color: AppColors.errorDark),
                      ),
                    ),
                    TextButton(
                      onPressed: _reRegisterFcm,
                      child: const Text('Re-enable',
                          style: TextStyle(color: AppColors.errorDark)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.errorDark),
                      onPressed: () =>
                          setState(() => _fcmTokenInvalid = false),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Row(
        children: [
          // Only show side nav on wide screens
          if (viewportInfo.isDesktop)
            // Container for the brand + navigation rail + sign-out
            Container(
              width: 220,
              decoration: const BoxDecoration(
                // You can replace this gradient with a single color if you prefer
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.sidebarStart,
                    AppColors.sidebarEnd,
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Logo/Title at the top
                  const SizedBox(height: 24),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.eco, color: AppColors.textPrimary, size: 24),
                      SizedBox(width: 8),
                      Text(
                        "Vinovoltaics",
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.dividerOnDark),

                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: OrganizationSelector(),
                  ),
                  const SizedBox(height: 6),
                  const NotificationsButton(),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.dividerOnDark),

                  // Navigation items
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: NavigationRail(
                        extended: true,
                        backgroundColor: Colors.transparent,
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectPage,
                        labelType: NavigationRailLabelType.none,
                        groupAlignment: -0.55,
                        destinations: [
                          NavigationRailDestination(
                            icon: Icon(MdiIcons.radioTower),
                            label: const Text('Stationary Sensors', style: TextStyle(fontSize: 14),),
                            padding: const EdgeInsets.only(bottom: 10),
                          ),
                          NavigationRailDestination(
                            icon: Icon(MdiIcons.chartLine),
                            label: const Text('Historical Trends', style: TextStyle(fontSize: 14),),
                            padding: const EdgeInsets.only(bottom: 10),
                          ),
                          NavigationRailDestination(
                            icon: Icon(MdiIcons.quadcopter),
                            label: const Text('Mobile Sensors', style: TextStyle(fontSize: 14),),
                            padding: const EdgeInsets.only(bottom: 10),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.analytics),
                            label: Text('Analytics', style: TextStyle(fontSize: 14)),
                            padding: EdgeInsets.only(bottom: 10),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.notifications_active),
                            label: Text('Alerts', style: TextStyle(fontSize: 14)),
                            padding: EdgeInsets.only(bottom: 10),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Sign Out button at the bottom
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: Icon(MdiIcons.logout, color: AppColors.textPrimary),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) => const SignOutDialog(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Main content area
          Expanded(
            child: viewportInfo.isMobilePortrait
                ? Column(
                    children: [
                      _buildMobileTopBar(context),
                      Expanded(
                        child: _pages[_selectedIndex],
                      ),
                    ],
                  )
                : viewportInfo.isMobileLandscape
                    ? Row(
                        children: [
                          _buildMobileLandscapeSidebar(context),
                          Expanded(
                            child: _pages[_selectedIndex],
                          ),
                        ],
                      )
                    : _pages[_selectedIndex],
          ),
        ],
            ),
          ),
        ],
      ),

      // Mobile bottom nav bar
      bottomNavigationBar: viewportInfo.isMobilePortrait
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: AppColors.textMuted,
              onTap: _selectPage,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.radar),
                  label: 'Stationary',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.show_chart),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.camera_alt),
                  label: 'Mobile',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.analytics),
                  label: 'Analytics',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.notifications_active),
                  label: 'Alerts',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildMobileTopBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.1 * 255).toInt()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.eco, color: AppColors.textPrimary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMobileOrganizationSelector(context),
              ),
              const NotificationsButton(iconColor: AppColors.textPrimary),
              IconButton(
                icon: Icon(MdiIcons.logout, color: AppColors.textPrimary),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) => const SignOutDialog(),
                  );
                },
                tooltip: 'Logout',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLandscapeSidebar(BuildContext context) {
    final primarySurface = Theme.of(context).colorScheme.primary;

    return Container(
      width: 104,
      color: primarySurface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactRail = constraints.maxHeight < 620;

            return Column(
              children: [
                SizedBox(height: compactRail ? 4 : 8),
                IconButton(
                  icon: const Icon(Icons.eco, color: AppColors.textPrimary),
                  onPressed: () => _showOrganizationMenu(context),
                  tooltip: 'Organization',
                  visualDensity: compactRail ? VisualDensity.compact : VisualDensity.standard,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Divider(
                    height: compactRail ? 12 : 20,
                    color: AppColors.dividerOnDark,
                  ),
                ),
                const NotificationsButton(iconColor: AppColors.textPrimary),
                IconButton(
                  icon: Icon(MdiIcons.logout, color: AppColors.textPrimary),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) => const SignOutDialog(),
                    );
                  },
                  tooltip: 'Logout',
                  visualDensity: compactRail ? VisualDensity.compact : VisualDensity.standard,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Divider(
                    height: compactRail ? 14 : 24,
                    color: AppColors.dividerOnDark,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _buildLandscapeNavItem(
                          label: 'Stationary Sensors',
                          iconData: MdiIcons.radioTower,
                          selected: _selectedIndex == 0,
                          onTap: () => _selectPage(0),
                          compactRail: compactRail,
                        ),
                      ),
                      Expanded(
                        child: _buildLandscapeNavItem(
                          label: 'Historical Trends',
                          iconData: MdiIcons.chartLine,
                          selected: _selectedIndex == 1,
                          onTap: () => _selectPage(1),
                          compactRail: compactRail,
                        ),
                      ),
                      Expanded(
                        child: _buildLandscapeNavItem(
                          label: 'Mobile Sensors',
                          iconData: MdiIcons.quadcopter,
                          selected: _selectedIndex == 2,
                          onTap: () => _selectPage(2),
                          compactRail: compactRail,
                        ),
                      ),
                      Expanded(
                        child: _buildLandscapeNavItem(
                          label: 'Analytics',
                          iconData: Icons.analytics,
                          selected: _selectedIndex == 3,
                          onTap: () => _selectPage(3),
                          compactRail: compactRail,
                        ),
                      ),
                      Expanded(
                        child: _buildLandscapeNavItem(
                          label: 'Alerts',
                          iconData: Icons.notifications_active,
                          selected: _selectedIndex == 4,
                          onTap: () => _selectPage(4),
                          compactRail: compactRail,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileOrganizationSelector(BuildContext context) {
    return InkWell(
      onTap: () {
        _showOrganizationMenu(context);
      },
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          final currentOrg = appState.selectedOrganization;
          return Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.textPrimary.withAlpha((0.2 * 255).toInt()),
                backgroundImage: currentOrg?.logoUrl != null
                    ? NetworkImage(currentOrg!.logoUrl!)
                    : null,
                child: currentOrg?.logoUrl == null
                    ? Text(
                        currentOrg?.name.isNotEmpty == true
                            ? currentOrg!.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  currentOrg?.name ?? 'No Organization',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.textPrimary.withAlpha((0.8 * 255).toInt()),
                size: 24,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLandscapeNavItem({
    required String label,
    required IconData iconData,
    required bool selected,
    required VoidCallback onTap,
    required bool compactRail,
  }) {
    final iconColor = selected ? AppColors.textPrimary : AppColors.textSecondary;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, color: iconColor, size: compactRail ? 24 : 26),
              if (!compactRail) ...[
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


    /*
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.white,
          /*flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF004D40), // teal dark
                Color(0xFF00796B), // teal
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),*/
        title: const Text('Vinovoltaics'),
      ),
      body: Row(
        children: [
          if (isWideScreen) NavigationRail(
            
            extended: true,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectPage,
            labelType: NavigationRailLabelType.none,
            //backgroundColor: Colors.blueGrey[50],
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.radar),
                label: Text('Stationary Sensors', style: TextStyle(fontSize: 14),),
                padding: EdgeInsets.only(bottom: 16),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.camera_alt),
                label: Text('Mobile Sensors', style: TextStyle(fontSize: 14),),
                padding: EdgeInsets.only(bottom: 16),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings', style: TextStyle(fontSize: 14),),
                padding: EdgeInsets.only(bottom: 16),
              ),
            ],
          ),
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: !isWideScreen ? BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueGrey,
        onTap: _selectPage,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Stationary',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Mobile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ) : null,
    );
  }
  */
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AppState appState = context.read<AppState>();
      // Note: getSettings has been moved to home_utils.dart
      // await getSettings(FirebaseAuth.instance.currentUser?.email, appState);
      // appState.addSite();
      appState.finalizeState();

      // Check whether the stored FCM token is still valid.
      await _checkFcmTokenStatus();
    });
  }

  /// Re-prompts for notification permission and refreshes the FCM token.
  Future<void> _reRegisterFcm() async {
    final granted = await _fcmService.requestPermissionAndSaveToken();
    if (mounted) {
      setState(() => _fcmTokenInvalid = !granted);
    }
  }

  /// Shows the banner only when the user previously registered for notifications
  /// (had a stored FCM token) but the token is now missing or invalidated.
  Future<void> _checkFcmTokenStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;

    final userDoc =
        await FirebaseFirestore.instance.doc('users/$uid').get();
    if (!mounted || !userDoc.exists) return;

    final data = userDoc.data();
    final tokens = data?['fcmTokens'];
    // Show banner only if the field exists (user previously registered)
    // but the array is now empty (tokens were pruned by the backend).
    final wasRegistered = data?.containsKey('fcmTokens') ?? false;
    final hasTokens = tokens is List && tokens.isNotEmpty;
    if (mounted) setState(() => _fcmTokenInvalid = wasRegistered && !hasTokens);
  }
}

