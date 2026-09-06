import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/services/sip_manager.dart';
import 'presentation/screens/dialpad_screen.dart';
import 'presentation/screens/in_call_screen.dart';
import 'presentation/screens/incoming_call_screen.dart';
import 'presentation/screens/settings_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred portrait orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Request Microphone & Notification permissions
  await _requestPermissions();

  // Initialize central SIP service
  final sipManager = SipManager();
  await sipManager.initialize(navKey: rootNavigatorKey);

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider<SipManager>.value(value: sipManager)],
      child: const SGTSoftphoneApp(),
    ),
  );
}

Future<void> _requestPermissions() async {
  if (!kIsWeb) {
    try {
      await Permission.microphone.request();
    } catch (e) {
      debugPrint('[Main] Request permissions error: $e');
    }
  }
}

class SGTSoftphoneApp extends StatelessWidget {
  const SGTSoftphoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SGT Softphone',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppConstants.backgroundLight,
        primaryColor: AppConstants.accentGreen,
        cardColor: AppConstants.surfaceLight,
        colorScheme: const ColorScheme.light(
          primary: AppConstants.accentGreen,
          secondary: AppConstants.accentGreen,
          surface: AppConstants.surfaceLight,
          error: AppConstants.accentRed,
          onPrimary: Colors.white,
          onSurface: AppConstants.textPrimary,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppConstants.surfaceLight,
          foregroundColor: AppConstants.textPrimary,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const DialpadScreen(),
        '/in_call': (context) => const InCallScreen(),
        '/incoming': (context) => const IncomingCallScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
