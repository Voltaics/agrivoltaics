import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'sites_panel.dart';
import 'zones_panel.dart';
import '../stationary_dashboard/stationary_dashboard.dart';
import '../mobile_dashboard/mobile_dashboard.dart';
import 'widgets/organization_menu_sheet.dart';
import 'widgets/organization_selector.dart';
import 'widgets/sign_out_dialog.dart';
import '../../app_state.dart';

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

  static final List<Widget> _pages = [
    const StationaryDashboardPage(),  // Stationary Sensors
    const MobileDashboardPage(),            // Mobile Sensors
  ];

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showOrganizationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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

    final isWideScreen = MediaQuery.of(context).size.width >= 1280 || screenHeight < screenWidth;
     return Scaffold(
      // 1) No AppBar here—removed entirely
      // 2) Row that holds [ Nav Rail (left) | Main Content (right) ]
      body: Row(
        children: [
          // Only show side nav on wide screens
          if (isWideScreen)
            // Container for the brand + navigation rail + sign-out
            Container(
              width: 220,
              decoration: const BoxDecoration(
                // You can replace this gradient with a single color if you prefer
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2D53DA), // start (primary color)
                    Color(0xFF1B2A99), // end (darker variant)
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
                      Icon(Icons.eco, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        "Vinovoltaics",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white38),
                  const SizedBox(height: 8),
                  
                  // Organization Selector
                  const OrganizationSelector(),
                  
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white38),

                  // Sites Panel
                  const SizedBox(
                    height: 250,
                    child: SitesPanel(),
                  ),

                  const Divider(color: Colors.white38),

                  // Zones Panel
                  const SizedBox(
                    height: 200,
                    child: ZonesPanel(),
                  ),

                  const Divider(color: Colors.white38),
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
                          label: const Text('Stationary Sensors', style: TextStyle(fontSize: 14),),
                          padding: const EdgeInsets.only(bottom: 16),
                        ),
                        NavigationRailDestination(
                          icon: Icon(MdiIcons.quadcopter),
                          label: const Text('Mobile Sensors', style: TextStyle(fontSize: 14),),
                          padding: const EdgeInsets.only(bottom: 16),
                        ),
                      ],
                    ),
                  ),

                  // Sign Out button at the bottom
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: Icon(MdiIcons.logout, color: Colors.white),
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
            child: !isWideScreen
                ? Column(
                    children: [
                      // Mobile AppBar with Organization Selector
                      Container(
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
                                const Icon(Icons.eco, color: Colors.white, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
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
                                              backgroundColor: Colors.white.withAlpha((0.2 * 255).toInt()),
                                              backgroundImage: currentOrg?.logoUrl != null
                                                  ? NetworkImage(currentOrg!.logoUrl!)
                                                  : null,
                                              child: currentOrg?.logoUrl == null
                                                  ? Text(
                                                      currentOrg?.name.isNotEmpty == true
                                                          ? currentOrg!.name[0].toUpperCase()
                                                          : '?',
                                                      style: const TextStyle(
                                                        color: Colors.white,
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
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Colors.white.withAlpha((0.8 * 255).toInt()),
                                              size: 24,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                // Logout button for mobile
                                IconButton(
                                  icon: Icon(MdiIcons.logout, color: Colors.white),
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
                      ),
                      // Page content
                      Expanded(
                        child: _pages[_selectedIndex],
                      ),
                    ],
                  )
                : _pages[_selectedIndex],
          ),
        ],
      ),

      // Mobile bottom nav bar
      bottomNavigationBar: !isWideScreen
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              onTap: _selectPage,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.radar),
                  label: 'Stationary',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.camera_alt),
                  label: 'Mobile',
                ),
              ],
            )
          : null,
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
    });
  }
}
