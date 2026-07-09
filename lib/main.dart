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
  // IMPORTANT: never rethrow here. If Firebase.initializeApp() fails
  // (bad google-services.json, no network on first launch, a stripped
  // class from a misconfigured ProGuard rule, etc.) the old code used
  // to rethrow, which crashes the whole app before runApp() is ever
  // called — on a release build that shows up to the user as nothing
  // but a black screen and no way to know why. Now we always get pixels
  // on screen: either the real app, or a clear error screen with a
  // retry button.
  bool firebaseReady = true;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[SwapNow] Firebase.initializeApp() failed: $e');
    firebaseReady = false;
  }

  if (!firebaseReady) {
    runApp(const _StartupErrorApp());
    return;
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

/// Shown only if Firebase itself fails to initialize — a rare, genuinely
/// unrecoverable-without-retry scenario (e.g. device has no network on
/// first cold start and Firebase can't fetch remote config). Gives the
/// user a way to retry instead of seeing a silent black screen.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 56, color: Color(0xFF5800B3)),
                const SizedBox(height: 20),
                const Text(
                  "Couldn't start SwapNow",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  "Please check your internet connection and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5800B3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  onPressed: () => main(),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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