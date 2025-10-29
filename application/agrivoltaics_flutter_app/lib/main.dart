import 'package:agrivoltaics_flutter_app/app_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:influxdb_client/api.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'app_constants.dart';
import 'pages/login.dart';

void main() async {
  // Initialize Firebase
  // (https://stackoverflow.com/a/63873689)
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform
  );

  // Register getIt
  final getIt = GetIt.instance;
  getIt.registerSingleton<InfluxDBClient>(InfluxDBClient(
    url: AppConstants.influxdbUrl,
    token: AppConstants.influxdbToken,
    org: AppConstants.influxdbOrg,
    bucket: AppConstants.influxdbBucket,
    debug: AppConstants.influxdbDebug // TODO: disable on release
  ));

  // Register Google Firebase Auth Provider
  GoogleAuthProvider googleAuthProvider = GoogleAuthProvider();
  googleAuthProvider.setCustomParameters({
    'prompt': 'select_account'
  });
  getIt.registerSingleton<GoogleAuthProvider>(googleAuthProvider);

  // Initialize timezone database
  tz.initializeTimeZones();

  // Launch application
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState())
      ], 
      child: const App(),
    )
    );

  
}

// Root application
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState(),
      child: MaterialApp(
        title: 'Vinovoltaics',
        /*theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey)
        ),*/
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2D53DA),           // Primary accent (buttons, selected icons)
            onPrimary: Colors.white,              // Text on primary
            secondary: Color(0xFF2D53DA),           // Optional
            onSecondary: Colors.white,
            background: Color(0xFFF2F5FD),        // App background
            onBackground: Colors.black,
            surface: Colors.white,                // Cards, nav rail
            onSurface: Colors.black,
            error: Colors.red,
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: Color(0xFFF2F5FD),
          cardTheme: CardThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 4,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 1,
          ),
          navigationRailTheme: const NavigationRailThemeData(
            backgroundColor: Colors.white,
            selectedIconTheme: IconThemeData(color: Color(0xFF2D53DA)),
            selectedLabelTextStyle: TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
            unselectedIconTheme: IconThemeData(color: Color.fromARGB(255, 255, 255, 255)),
            unselectedLabelTextStyle: TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
            indicatorColor: Color.fromARGB(255, 255, 255, 255), // No oval
            labelType: NavigationRailLabelType.none,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF2D53DA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),


        home: const LoginPage(),
        // home: const HomePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}