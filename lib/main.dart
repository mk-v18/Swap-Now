import 'package:credbro/splash_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:media_kit/media_kit.dart';
import 'chats/chatscreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  debugPrint('[FCM] Background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only the bare minimum needed before the first frame can paint.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[SwapNow] FATAL: Firebase.initializeApp() failed: $e');
    rethrow;
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Get pixels on screen ASAP — splash screen shows immediately.
  runApp(SwapNowApp(navigatorKey: navigatorKey));

  // Everything below runs AFTER the first frame is drawn, so it can
  // never block or delay the splash screen from appearing.
  _deferAppCheckInit();
  _deferMediaKitInit();
  _deferAdsInit();
}

void _deferAppCheckInit() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
        kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      );
    } catch (e) {
      debugPrint('[SwapNow] AppCheck activation error: $e');
    }
  });
}

void _deferMediaKitInit() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      debugPrint('[SwapNow] MediaKit init error: $e');
    }
  });
}

void _deferAdsInit() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('[SwapNow] MobileAds init error: $e');
    }
  });
}

class SwapNowApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const SwapNowApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwapNow',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        fontFamily: 'Poppins',
        primaryColor: const Color(0xFF6A0DAD),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A0DAD)),
        useMaterial3: true,
      ),
      home: SplashScreen(navigatorKey: navigatorKey),
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId:        args['chatId']        as String? ?? '',
              receiverId:    args['receiverId']    as String? ?? '',
              receiverName:  args['receiverName']  as String? ?? 'Unknown',
              receiverImage: args['receiverImage'] as String? ?? '',
            ),
          );
        }
        return null;
      },
    );
  }
}