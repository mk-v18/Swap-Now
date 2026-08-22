import 'package:amoeba/splash_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:media_kit/media_kit.dart';
import 'admin panel/ad_response.dart';
import 'admin panel/admin_categories_page.dart';
import 'admin panel/admin_help_queries.dart';
import 'chats/chatscreen.dart';
import 'chats/exchange_history_page.dart';
import 'chats/swap_requests_page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  debugPrint('[FCM] Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX (white-screen root cause): Firebase.initializeApp() is a fast,
  // local SDK init -- fine to await before runApp(). It's NOT the thing
  // causing the 3-5s blank screen.
  bool coreFirebaseFailed = false;
  try {
    await Firebase.initializeApp();
    // Only needs Firebase.initializeApp() to have succeeded -- doesn't
    // need to wait on AppCheck too, so it's registered right here.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[SwapNow] Firebase.initializeApp failed: $e');
    coreFirebaseFailed = true;
  }

  // FIX (white-screen root cause): FirebaseAppCheck.instance.activate() is
  // a genuine network round trip -- Play Integrity on Android / DeviceCheck
  // on iOS -- and used to be `await`-ed here, BEFORE runApp() was ever
  // called. Flutter can't paint anything until runApp() runs, so for
  // however long that attestation call took, the user was staring at the
  // bare native launch background (plain white by default). That's almost
  // certainly the 3-5s blank screen being reported.
  //
  // It's now fired without awaiting: it finishes in the background, hidden
  // behind the splash screen's own ~4.5s on-screen animation instead of
  // blocking the first frame. Nothing before this point needs an AppCheck
  // token yet.
  if (!coreFirebaseFailed) {
    _activateAppCheck();
  }

  // FIX (dead code): _StartupErrorApp was defined but never actually
  // shown anywhere -- Firebase failures were swallowed and the app
  // launched normally regardless, meaning a user whose Firebase truly
  // failed to init would hit broken auth/Firestore calls further in with
  // no explanation. Now it's actually used for that case.
  runApp(
    coreFirebaseFailed
        ? const _StartupErrorApp()
        : SwapNowApp(navigatorKey: navigatorKey),
  );

  _deferMediaKitInit();
  _deferAdsInit();
}

void _activateAppCheck() {
  FirebaseAppCheck.instance
      .activate(
    androidProvider:
    kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider:
    kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
  )
      .catchError((e) {
    // Non-fatal: app still works without AppCheck, just less protected.
    debugPrint('[SwapNow] AppCheck activation failed: $e');
  });
}

/// Shown only if Firebase.initializeApp() itself fails -- a rare, genuinely
/// unrecoverable-without-retry scenario (e.g. device has no network on
/// first cold start). Gives the user a way to retry instead of a broken
/// app with silent Firebase failures downstream.
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
      title: 'Amoeba',
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

        // Swap request notifications (sent / accepted / declined)
        // deep-link here, landing on the matching tab.
        //   tab 0 = Incoming, tab 1 = Active, tab 2 = Sent
        if (settings.name == '/swap-requests') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (_) => SwapRequestsPage(
              initialTab: (args['tab'] as int?) ?? 0,
            ),
          );
        }

        // Exchange completed/cancelled notifications deep-link here.
        if (settings.name == '/exchange-history') {
          return MaterialPageRoute(builder: (_) => const ExchangeHistoryPage());
        }

        // Admin "new help query submitted" notifications deep-link here.
        // No arguments needed -- AdminHelpQueriesPage streams the full
        // list itself; the admin taps the relevant card once inside.
        if (settings.name == '/admin-help-queries') {
          return MaterialPageRoute(builder: (_) => const AdminHelpQueriesPage());
        }

        // NEW: ad request notifications deep-link here.
        //   isAdmin: true  → admin's "new ad request submitted" push
        //   isAdmin: false → submitter's "approved"/"rejected" push
        if (settings.name == '/ad-responses') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (_) => AdResponsesPage(
              isAdmin: (args['isAdmin'] as bool?) ?? false,
            ),
          );
        }

        // NEW: "new suggestion submitted" notifications deep-link here.
        // There's no dedicated suggestions-review screen yet, so this
        // lands the admin on the categories hub as the closest existing
        // screen -- build a SuggestionsAdminPage + register its own route
        // if you want a direct deep link instead.
        if (settings.name == '/admin-categories') {
          return MaterialPageRoute(builder: (_) => const AdminCategoriesPage());
        }

        return null;
      },
    );
  }
}