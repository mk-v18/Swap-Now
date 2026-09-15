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

  // FIX(re-login-every-launch, root cause): SplashScreen's navigation timing
  // got faster (see splash_screen.dart), which is good, but it exposed a
  // pre-existing race that used to be hidden by the old flat 4.5s delay:
  // Wrapper's very first Firestore read (to look up the signed-in user's
  // profile doc) could now land BEFORE App Check finished activating.
  // If App Check enforcement is on for Firestore/Auth, a request that goes
  // out before App Check is ready can come back rejected, which Wrapper's
  // error handling can misread as "this session is invalid" and sign the
  // user out -- on every single launch, since the timing was consistently
  // losing the race, not occasionally. Exposing this as an awaited Future
  // (instead of the previous fire-and-forget) lets SplashScreen actually
  // wait for App Check before handing off to Wrapper, restoring the
  // ordering the old delay used to give us for free, without bringing
  // back a multi-second flat wait for everyone.
  final appCheckReady = firebaseInit.then((_) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    return _activateAppCheck();
  }).catchError((e) {
    debugPrint('[SwapNow] Firebase.initializeApp failed: $e');
    // SplashScreen awaits firebaseInit separately and shows its own retry
    // UI for this case -- nothing else to do with the error here.
  });

  runApp(SwapNowApp(
    navigatorKey: navigatorKey,
    firebaseInit: firebaseInit,
    appCheckReady: appCheckReady,
  ));

  _deferMediaKitInit();
  _deferAdsInit();
}

Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
      kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
      kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
  } catch (e) {
    // Non-fatal: app still works without AppCheck, just less protected.
    debugPrint('[SwapNow] AppCheck activation failed: $e');
    return;
  }

  // FIX(slow OTP send): App Check's Play Integrity provider is slow on
  // its FIRST token fetch -- a cold call to Play Integrity commonly
  // takes several seconds (10-15s is normal on some devices/networks)
  // because it's a real round trip to Google Play services, not a local
  // computation. Phone Auth's verifyPhoneNumber() needs a valid App
  // Check token before it can even ask Firebase to send the SMS, so if
  // nothing has fetched one yet, that entire Play Integrity round trip
  // happened to land right when the user tapped "Continue" on the OTP
  // page -- which is exactly the multi-second spinner being reported.
  // Fetching (and letting the SDK cache) a token here, immediately
  // after activation during app startup, means that round trip happens
  // in the background while the user is still looking at the splash/
  // home screen instead of blocking the OTP flow later. Later calls
  // (including the one verifyPhoneNumber() makes internally) reuse the
  // cached token until it's close to expiry, so this only pays the cold
  // fetch cost once per app session.
  //
  // A plain getToken() (no force-refresh) still warms the cache the
  // first time -- nothing is cached yet on a fresh session -- but
  // reuses whatever's already there afterwards, same as every other
  // caller asking App Check for a token.
  try {
    await FirebaseAppCheck.instance.getToken();
  } catch (e) {
    debugPrint('[SwapNow] AppCheck token pre-fetch failed: $e');
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
  final Future<FirebaseApp> firebaseInit;
  final Future<void> appCheckReady;
  const SwapNowApp({
    super.key,
    required this.navigatorKey,
    required this.firebaseInit,
    required this.appCheckReady,
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
      // renders its own retry UI if it fails. appCheckReady lets it also
      // wait for App Check specifically before handing off to Wrapper --
      // see the comment on appCheckReady in main() for why that ordering
      // matters.
      home: SplashScreen(
        navigatorKey: navigatorKey,
        firebaseInit: firebaseInit,
        appCheckReady: appCheckReady,
      ),
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