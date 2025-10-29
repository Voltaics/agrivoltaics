import 'dart:convert';

import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:agrivoltaics_flutter_app/auth.dart';
import 'package:agrivoltaics_flutter_app/pages/login.dart';
import 'package:agrivoltaics_flutter_app/pages/settings.dart';
import 'package:agrivoltaics_flutter_app/pages/home/notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';


import '../dashboard/dashboard_new.dart';
import '../mobile_dashboard/mobile_dashboard.dart';

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
    TabbedDashboardPage(),         // Stationary Sensors
    MobileDashboardPage(),   // Mobile Sensors
    SettingsPage(),          // Settings
  ];

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
              decoration: BoxDecoration(
                // You can replace this gradient with a single color if you prefer
                gradient: const LinearGradient(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
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
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white38),
                  const SizedBox(height: 8),

                  // Our actual NavRail, but transparent so the gradient shows through
                  Expanded(
                    child: NavigationRail(
                      extended: true,
                      backgroundColor: Colors.transparent,
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectPage,
                      labelType: NavigationRailLabelType.none,
                      // extended: true, // If you want wide rail with text shown
                      destinations: [
                        NavigationRailDestination(
                          icon: Icon(MdiIcons.radioTower),
                          label: Text('Stationary Sensors', style: TextStyle(fontSize: 14),),
                          padding: EdgeInsets.only(bottom: 16),
                        ),
                        NavigationRailDestination(
                          icon: Icon(MdiIcons.quadcopter),
                          label: Text('Mobile Sensors', style: TextStyle(fontSize: 14),),
                          padding: EdgeInsets.only(bottom: 16),
                        ),
                        /* settings already found in stationary dashboard
                          NavigationRailDestination(
                          icon: Icon(Icons.settings),
                          label: Text('Settings', style: TextStyle(fontSize: 14),),
                          padding: EdgeInsets.only(bottom: 16),
                        ),*/
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
            child: _pages[_selectedIndex],
          ),
        ],
      ),

      // 3) Mobile bottom nav bar remains
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
      await getSettings(FirebaseAuth.instance.currentUser?.email, appState);
      // appState.addSite();
      appState.finalizeState();
    });
  }
}

/*

Sign Out button
- Signs out user from Firebase and rest of application

*/
class SignOutButton extends StatelessWidget {
  const SignOutButton({
    super.key,
  });

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
                builder: (BuildContext context) => SignOutDialog()
              );
            },
            icon: Icon(MdiIcons.logout)
          ),
        );
      }
    );
  }
}

/*

Sign Out Dialog
- Dialog which prompts whether user would like to sign out

*/
class SignOutDialog extends StatelessWidget {
  const SignOutDialog({
    super.key,
  });

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
              MaterialPageRoute(
                builder: (context) => const LoginPage()
              )
            );
          },
          child: const Text('Sign out')
        )
      ]
    );
  }
}

class AppSettings {
  AppSettings(this.body, this.siteChecked);
  AppNotificationBody body;
  String siteChecked;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      AppNotificationBody.fromJson(json['settings']),
      json['site1'].toString().split('/')[0]
    );
  }
}

Future<void> getSettings(String? email, AppState appstate) async {
  try {
  http.Response response = await http.get(Uri.parse('https://vinovoltaics-notification-api-6ajy6wk4ca-ul.a.run.app/getSettings?email=${email}'));
  
  if (response.statusCode == 200) {
    appstate.sites = [];
    bool siteChecked = false;
    String siteNickName;
    bool zoneChecked = false;
    String zoneNickName;
    bool temperature = false;
    bool humidity = false;
    bool frost = false;
    bool rain = false;
    bool soil = false;
    bool light = false;

    for (int i = 0; i < jsonDecode(response.body)['settings'].length - 3; i++) {
      for (int j = 0; j < jsonDecode(response.body)['settings']['site${i+1}'].length - 2; j++) {
        siteChecked = json.decode(response.body)['settings']['site${i+1}']['site_checked'];
        siteNickName = json.decode(response.body)['settings']['site${i+1}']['nickName'];
        zoneChecked = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['zone_checked'];
        zoneNickName = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['nickName'];
        temperature = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['temperature'];
        humidity = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['humidity'];
        frost = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['frost'];
        rain = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['rain'];
        soil = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['soil'];
        light = json.decode(response.body)['settings']['site${i+1}']['zone${j+1}']['light'];

        if (j == 0) {
          appstate.addSiteFromDB(siteChecked, siteNickName, zoneChecked, zoneNickName, humidity, temperature, light, frost, rain, soil);
        } else {
          appstate.addZoneFromDB(i, zoneChecked, zoneNickName, humidity, temperature, light, frost, rain, soil);
        }
      }
    }

    appstate.singleGraphToggle = json.decode(response.body)['settings']['singleGraphToggle'];
    appstate.timezone = tz.getLocation(json.decode(response.body)['settings']['timeZone']); 
    appstate.returnDataValue = json.decode(response.body)['settings']['returnDataFilter'];
  }

  // ignore: empty_catches
  } catch (e) {
    print(e);
  }
}
