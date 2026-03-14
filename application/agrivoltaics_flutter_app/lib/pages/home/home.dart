import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'notifications.dart';
import 'sites_panel.dart';
import 'zones_panel.dart';
import '../stationary_dashboard/stationary_dashboard.dart';
import '../mobile_dashboard/mobile_dashboard.dart';
import '../historical_dashboard/historical_dashboard.dart';
import '../alerts/alerts_page.dart';
import '../analytics_dashboard/analytics_dashboard.dart';
import 'widgets/organization_menu_sheet.dart';
import 'widgets/organization_selector.dart';
import 'widgets/sign_out_dialog.dart';
import '../../app_state.dart';
import '../../services/fcm_service.dart';

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const OrganizationMenuSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Distinguish true desktop from landscape-mobile so the overflowing
    // 220-px sidebar is never shown on phones rotated to landscape.
    final isDesktop = screenWidth >= 1280;
    final isLandscapeMobile = !isDesktop && (screenHeight < screenWidth);
    final isPortraitMobile = !isDesktop && !isLandscapeMobile;

    return Scaffold(
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
                // ── Desktop: full 220-px branded sidebar ────────────────
                if (isDesktop)
                  Container(
                    width: 220,
                    decoration: const BoxDecoration(
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
                        // Logo/Title
                        const SizedBox(height: 24),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.eco,
                                color: AppColors.textPrimary, size: 24),
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
                        const SizedBox(height: 8),

                        // Organization Selector
                        const OrganizationSelector(),

                        const SizedBox(height: 8),
                        const Divider(color: AppColors.dividerOnDark),

                        // Sites Panel — flexible up to 250px so it
                        // shrinks proportionally on small laptop screens.
                        // flex 5:4 matches the 250:200 max-height ratio.
                        Flexible(
                          flex: 5,
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 250),
                            child: const SitesPanel(),
                          ),
                        ),

                        const Divider(color: AppColors.dividerOnDark),

                        // Zones Panel — flexible up to 200px
                        Flexible(
                          flex: 4,
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxHeight: 200),
                            child: const ZonesPanel(),
                          ),
                        ),

                        const Divider(color: AppColors.dividerOnDark),
                        const SizedBox(height: 8),

                        // Navigation items
                        Expanded(
                          child: NavigationRail(
                            extended: true,
                            backgroundColor: Colors.transparent,
                            selectedIndex: _selectedIndex,
                            onDestinationSelected: _selectPage,
                            labelType: NavigationRailLabelType.none,
                            destinations: [
                              NavigationRailDestination(
                                icon: Icon(MdiIcons.radioTower),
                                label: const Text('Stationary Sensors',
                                    style: TextStyle(fontSize: 14)),
                                padding:
                                    const EdgeInsets.only(bottom: 16),
                              ),
                              NavigationRailDestination(
                                icon: Icon(MdiIcons.chartLine),
                                label: const Text('Historical Trends',
                                    style: TextStyle(fontSize: 14)),
                                padding:
                                    const EdgeInsets.only(bottom: 16),
                              ),
                              NavigationRailDestination(
                                icon: Icon(MdiIcons.quadcopter),
                                label: const Text('Mobile Sensors',
                                    style: TextStyle(fontSize: 14)),
                                padding:
                                    const EdgeInsets.only(bottom: 16),
                              ),
                              const NavigationRailDestination(
                                icon: Icon(Icons.analytics),
                                label: Text('Analytics',
                                    style: TextStyle(fontSize: 14)),
                                padding:
                                    EdgeInsets.only(bottom: 16),
                              ),
                              NavigationRailDestination(
                                icon:
                                    const Icon(Icons.notifications_active),
                                label: const Text('Alerts',
                                    style: TextStyle(fontSize: 14)),
                                padding:
                                    const EdgeInsets.only(bottom: 16),
                              ),
                            ],
                          ),
                        ),

                        // Notifications button
                        const NotificationsButton(),

                        // Sign Out button at the bottom
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IconButton(
                            icon: Icon(MdiIcons.logout,
                                color: AppColors.textPrimary),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) =>
                                    const SignOutDialog(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Landscape-mobile: compact 72-px icon-only rail ───────
                if (isLandscapeMobile)
                  Container(
                    width: 72,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.sidebarStart,
                          AppColors.sidebarEnd,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      right: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 6),

                          // Org selector: avatar + truncated name + chevron
                          Consumer<AppState>(
                            builder: (context, appState, _) {
                              final org =
                                  appState.selectedOrganization;
                              return Tooltip(
                                message: org?.name ?? 'Switch Organization',
                                child: InkWell(
                                  onTap: () =>
                                      _showOrganizationMenu(context),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor:
                                              AppColors.textPrimary
                                                  .withAlpha(
                                                      (0.25 * 255).toInt()),
                                          backgroundImage:
                                              org?.logoUrl != null
                                                  ? NetworkImage(
                                                      org!.logoUrl!)
                                                  : null,
                                          child: org?.logoUrl == null
                                              ? Text(
                                                  org?.name.isNotEmpty ==
                                                          true
                                                      ? org!.name[0]
                                                          .toUpperCase()
                                                      : '?',
                                                  style: const TextStyle(
                                                    color: AppColors
                                                        .textPrimary,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          org?.name ?? 'No Org',
                                          style: TextStyle(
                                            color: AppColors.textPrimary
                                                .withAlpha(
                                                    (0.85 * 255).toInt()),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: AppColors.textPrimary
                                              .withAlpha(
                                                  (0.6 * 255).toInt()),
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const Divider(color: AppColors.dividerOnDark),

                          // Icon-only navigation rail
                          Expanded(
                            child: NavigationRail(
                              extended: false,
                              backgroundColor: Colors.transparent,
                              selectedIndex: _selectedIndex,
                              onDestinationSelected: _selectPage,
                              labelType: NavigationRailLabelType.none,
                              minWidth: 56,
                              destinations: [
                                NavigationRailDestination(
                                  icon: Icon(MdiIcons.radioTower),
                                  label: const Text('Stationary'),
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(MdiIcons.chartLine),
                                  label: const Text('History'),
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(MdiIcons.quadcopter),
                                  label: const Text('Mobile'),
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                ),
                                const NavigationRailDestination(
                                  icon: Icon(Icons.analytics),
                                  label: Text('Analytics'),
                                  padding:
                                      EdgeInsets.only(bottom: 8),
                                ),
                                NavigationRailDestination(
                                  icon: const Icon(
                                      Icons.notifications_active),
                                  label: const Text('Alerts'),
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                ),
                              ],
                            ),
                          ),

                          // Notifications button
                          const NotificationsButton(),

                          // Sign Out
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: IconButton(
                              icon: Icon(MdiIcons.logout,
                                  color: AppColors.textPrimary),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      const SignOutDialog(),
                                );
                              },
                              tooltip: 'Logout',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Main content area ────────────────────────────────────
                Expanded(
                  child: isDesktop || isLandscapeMobile
                      // Desktop & landscape mobile: page fills the
                      // remaining space directly — no redundant top-bar.
                      ? _pages[_selectedIndex]
                      // Portrait mobile only: show the top bar with
                      // org-selector + notifications + logout.
                      : Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).colorScheme.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha((0.1 * 255).toInt()),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.eco,
                                          color: AppColors.textPrimary,
                                          size: 24),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              _showOrganizationMenu(
                                                  context),
                                          child: Consumer<AppState>(
                                            builder:
                                                (context, appState, child) {
                                              final currentOrg = appState
                                                  .selectedOrganization;
                                              return Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor:
                                                        AppColors.textPrimary
                                                            .withAlpha((0.2 *
                                                                    255)
                                                                .toInt()),
                                                    backgroundImage:
                                                        currentOrg?.logoUrl !=
                                                                null
                                                            ? NetworkImage(
                                                                currentOrg!
                                                                    .logoUrl!)
                                                            : null,
                                                    child: currentOrg
                                                                ?.logoUrl ==
                                                            null
                                                        ? Text(
                                                            currentOrg?.name
                                                                        .isNotEmpty ==
                                                                    true
                                                                ? currentOrg!
                                                                    .name[0]
                                                                    .toUpperCase()
                                                                : '?',
                                                            style:
                                                                const TextStyle(
                                                              color: AppColors
                                                                  .textPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 14,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      currentOrg?.name ??
                                                          'No Organization',
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .textPrimary,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.keyboard_arrow_down,
                                                    color: AppColors.textPrimary
                                                        .withAlpha((0.8 * 255)
                                                            .toInt()),
                                                    size: 24,
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      // Notifications button for mobile
                                      const NotificationsButton(),
                                      // Logout button for mobile
                                      IconButton(
                                        icon: Icon(MdiIcons.logout,
                                            color: AppColors.textPrimary),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (BuildContext context) =>
                                                const SignOutDialog(),
                                          );
                                        },
                                        tooltip: 'Logout',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Page content
                            Expanded(
                              child: _pages[_selectedIndex],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Bottom nav bar only for portrait mobile — landscape mobile uses the
      // compact side rail instead.
      bottomNavigationBar: isPortraitMobile
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

    final data = userDoc.data() as Map<String, dynamic>?;
    final tokens = data?['fcmTokens'];
    // Show banner only if the field exists (user previously registered)
    // but the array is now empty (tokens were pruned by the backend).
    final wasRegistered = data?.containsKey('fcmTokens') ?? false;
    final hasTokens = tokens is List && (tokens as List).isNotEmpty;
    if (mounted) setState(() => _fcmTokenInvalid = wasRegistered && !hasTokens);
  }
}
