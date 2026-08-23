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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX (white-screen root cause, round 2): the earlier fix moved
  // FirebaseAppCheck.activate() off the blocking path, but
  // `await Firebase.initializeApp()` was still sitting BEFORE runApp().
  // Nothing paints -- not even the splash animation -- until runApp()
  // runs, so whatever the OS shows as its native launch background
  // (plain white unless launch_background.xml / LaunchScreen.storyboard
  // has been customized) is exactly what the user sees for however long
  // Firebase.initializeApp() takes. That's the "still white for a long
  // time" report: it happens BEFORE Flutter ever gets a chance to draw
  // the purple splash screen, so none of the previous splash-side fixes
  // touch it at all.
  //
  // Fix: start Firebase.initializeApp() but don't block on it here. Call
  // runApp() immediately so the splash paints on the very first frame,
  // and hand SplashScreen the in-flight Future so it can await it
  // internally before touching anything that needs Firebase core to be
  // ready (FirebaseAuth, Firestore).
  final firebaseInit = Firebase.initializeApp();

  firebaseInit.then((_) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _activateAppCheck();
  }).catchError((e) {
    debugPrint('[SwapNow] Firebase.initializeApp failed: $e');
    // SplashScreen awaits this same future and shows its own retry UI --
    // no separate navigation needed here.
  });

  runApp(SwapNowApp(navigatorKey: navigatorKey, firebaseInit: firebaseInit));

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
  final Future<FirebaseApp> firebaseInit;
  const SwapNowApp({
    super.key,
    required this.navigatorKey,
    required this.firebaseInit,
  });

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
      // firebaseInit is now the source of truth for "is Firebase ready" --
      // SplashScreen awaits it before touching FirebaseAuth/Firestore, and
      // renders its own retry UI if it fails.
      home: SplashScreen(navigatorKey: navigatorKey, firebaseInit: firebaseInit),
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