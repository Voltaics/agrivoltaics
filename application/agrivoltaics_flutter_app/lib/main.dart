import 'package:agrivoltaics_flutter_app/app_colors.dart';
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
import 'services/readings_service.dart';
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

  // Initialize ReadingsService (load reading definitions from Firestore)
  final readingsService = ReadingsService();
  await readingsService.loadReadings();

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
            primary:     AppColors.primary,
            onPrimary:   Colors.white,
            secondary:   AppColors.primary,
            onSecondary: Colors.white,
            surface:     AppColors.surface,
            onSurface:   Colors.black,
            error:       AppColors.error,
            onError:     Colors.white,
          ),
          scaffoldBackgroundColor: AppColors.scaffoldBackground,
          cardTheme: CardThemeData(
            color: AppColors.surface,
            surfaceTintColor: AppColors.surface,
            elevation: 4,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.surface,
            foregroundColor: Colors.black,
            elevation: 1,
          ),
          navigationRailTheme: const NavigationRailThemeData(
            backgroundColor: AppColors.surface,
            selectedIconTheme: IconThemeData(color: AppColors.primary),
            selectedLabelTextStyle: TextStyle(color: Colors.white),
            unselectedIconTheme: IconThemeData(color: Colors.white),
            unselectedLabelTextStyle: TextStyle(color: Colors.white),
            indicatorColor: Colors.white, // No oval
            labelType: NavigationRailLabelType.none,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
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