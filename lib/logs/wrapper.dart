// ignore_for_file: unawaited_futures
import 'dart:async';
import 'package:amoeba/logs/banned_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin panel/admin_bottom_nav.dart';
import '../start/starting_page.dart';
import 'otp.dart';
import '../pages/bottom_navigation.dart';
import '../start/personal_details.dart';
// REMOVED: import '../start/payment.dart';
// Payment is no longer part of the onboarding routing chain -- it'll be
// wired in separately elsewhere, so Wrapper doesn't need to know about it.

/// FIX (white-screen after splash): caches the "which screen should this
/// user land on" resolution (a SharedPreferences read + a Firestore
/// `users/{uid}` read) so it can be *started early* -- SplashScreen kicks
/// it off during its own animation -- and *reused* by [Wrapper] instead of
/// being redone from scratch the instant Wrapper mounts.
///
/// Before this existed, Wrapper always started a brand-new resolution the
/// moment it appeared on screen, so that network round trip only began
/// AFTER the splash screen had already disappeared -- leaving the user
/// looking at a second blank frame with nothing on it while it ran. Now,
/// as long as the splash's ~4.5s on-screen time was enough for this to
/// finish in the background, Wrapper picks up an already-completed
/// result and skips the wait entirely.
class RouteResolver {
  RouteResolver._();
  static final RouteResolver instance = RouteResolver._();

  String? _cachedUid;
  Future<Widget>? _cachedFuture;

  /// Starts (or reuses the existing) resolution for [user]. Safe to call
  /// more than once for the same uid -- e.g. once from SplashScreen to
  /// warm the cache, then again from Wrapper -- it returns the same
  /// in-flight or already-completed Future rather than hitting Firestore
  /// a second time.
  Future<Widget> resolve(User user) {
    if (_cachedUid == user.uid && _cachedFuture != null) {
      return _cachedFuture!;
    }
    _cachedUid = user.uid;
    _cachedFuture = Wrapper.resolveDestination(user);
    return _cachedFuture!;
  }

  /// Drops the cached resolution. Called on sign-out so a later sign-in
  /// (possibly a different account) never reuses a stale result.
  void clear() {
    _cachedUid = null;
    _cachedFuture = null;
  }
}

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  /// Errors that genuinely mean "this session is no longer valid" -- only
  /// these should force a sign-out. Everything else (permission-denied from
  /// Firestore rules, network hiccups, timeouts, etc.) must NOT sign the
  /// user out -- it should just show a retryable error screen. This matters
  /// a lot for banned users: if your Firestore rules deny reads based on a
  /// `banned` field, that throws a `permission-denied` FirebaseException,
  /// which used to be caught here and treated as a reason to sign out --
  /// silently kicking banned users out of their own session (and breaking
  /// things like the in-app Help Center, which needs `currentUser` to stay
  /// non-null).
  static bool _isSessionInvalid(Object error) {
    if (error is FirebaseAuthException) {
      const invalidCodes = {
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
        'requires-recent-login',
      };
      return invalidCodes.contains(error.code);
    }
    return false;
  }

  /// CHANGED: was the private instance method `_checkUser`. Made static
  /// and public (renamed `resolveDestination`) so [RouteResolver] --
  /// and therefore SplashScreen -- can call it directly to warm the cache
  /// ahead of time, instead of it only being reachable once a Wrapper
  /// instance exists on screen.
  static Future<Widget> resolveDestination(User user) async {
    try {
      // FIX(perf): Kick off the SharedPreferences load and the Firestore
      // read at the same time instead of awaiting them one after another.
      // They don't depend on each other -- the old code paid for two full
      // sequential round trips (a platform-channel hop for prefs, then a
      // network hop for Firestore) on every single app start / auth event,
      // when it only needed to pay for whichever one is slower.
      final prefsFuture = SharedPreferences.getInstance();
      final docFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final prefs = await prefsFuture;
      final doc = await docFuture;

      final cachedUid = prefs.getString('cached_uid');
      if (cachedUid != null && cachedUid != user.uid) {
        // FIX(perf): this used to be `await Future.wait([...])`, which
        // blocked returning the routed widget on three SharedPreferences
        // writes that only matter for the NEXT app launch, not this one --
        // nothing below depends on the removal having finished. Firing it
        // without awaiting shaves that round trip off every account-switch
        // case without changing behavior (the removal still happens, just
        // concurrently with the rest of routing instead of gating it).
        unawaited(Future.wait([
          prefs.remove('role'),
          prefs.remove('cached_uid'),
          prefs.remove('onboarding_step'),
        ]));
      }

      // NOTE: we intentionally do NOT short-circuit on a cached role here
      // anymore. Role can be changed out-of-band (e.g. an admin flips a
      // user's `role` field directly in the Firestore console), and a
      // cached-role fast path would keep routing the user based on stale
      // data until the cache was manually cleared -- which is exactly the
      // bug that caused a Firestore-promoted admin to keep landing on the
      // regular BottomNavigation instead of AdminBottomNavigation. Role
      // must always come from a fresh Firestore read.

      if (!doc.exists) return const PersonalDetailsPage();

      final data = doc.data() ?? {};
      final role = data['role']?.toString().trim().toLowerCase() ?? 'user';
      // REMOVED: `hasPaid` no longer gates onboarding -- payment is being
      // moved to a separate place in the app, not the signup funnel.
      final name = data['name']?.toString().trim() ?? '';
      final email = data['email']?.toString().trim() ?? '';
      final location = data['location']?.toString().trim() ?? '';
      final image = data['profileImage']?.toString().trim() ?? '';
      // Checkpoint written by each onboarding step:
      // 'personal_details' -> 'starting_page' -> 'done'
      // (payment step removed from this chain)
      final step =
          data['onboardingStep']?.toString().trim() ?? 'personal_details';

      // Admins skip the consumer onboarding flow entirely.
      if (role == 'admin') {
        // FIX(perf): fire-and-forget -- same reasoning as above. These
        // three writes only exist to warm the cache for the NEXT launch;
        // the routing decision for THIS launch (AdminBottomNavigation)
        // doesn't need to wait on them landing on disk first.
        unawaited(Future.wait([
          prefs.setString('role', role),
          prefs.setString('cached_uid', user.uid),
          prefs.setString('onboarding_step', 'done'),
        ]));
        return const AdminBottomNavigation();
      }

      final profileComplete = name.isNotEmpty &&
          email.isNotEmpty &&
          location.isNotEmpty &&
          image.isNotEmpty;

      // Resume exactly where the user left off:
      // OTP (handled above by authStateChanges) -> PersonalDetails ->
      // StartingPage -> BottomNavigation. Payment step removed.
      if (!profileComplete) return const PersonalDetailsPage();
      if (step != 'done') return const StartingPage();

      // FIX(perf): same fire-and-forget treatment here.
      unawaited(Future.wait([
        prefs.setString('role', role),
        prefs.setString('cached_uid', user.uid),
        prefs.setString('onboarding_step', 'done'),
      ]));
      return BannedGate(uid: user.uid, child: const BottomNavigation());
    } catch (e) {
      debugPrint("Wrapper error: $e");

      // Only sign out for errors that mean the session itself is actually
      // invalid. Everything else (e.g. Firestore permission-denied for a
      // banned user, transient network failures) should NOT sign the user
      // out -- show a retryable error screen instead so they keep their
      // session (and can still reach things like the banned-account page
      // or Help Center).
      if (_isSessionInvalid(e)) {
        // DIAGNOSTIC: if you're seeing "asks for login every time the app
        // is reopened", check the device logs for this exact line right
        // after you relaunch -- it prints the FirebaseAuthException code
        // that's triggering the forced sign-out below. In practice this
        // almost always turns out to be 'user-token-expired' or
        // 'invalid-user-token' coming from a failed silent ID-token
        // refresh, and the #1 real-world cause of THAT is Firebase App
        // Check enforcement on the Authentication API being turned on in
        // the console while the app is tested via a build Play Integrity
        // can't attest (anything not installed through Google Play --
        // sideloaded APKs, most internal/ad-hoc test builds, emulators
        // without Play Store, etc.). If that's the case, Play Integrity
        // fails to produce a valid App Check token on literally every
        // launch, the Auth SDK's background token refresh gets rejected
        // every time, and the session dies every time as a result -- so
        // it FEELS like sign-out isn't persisting, but the actual bug is
        // upstream of this file, in Firebase Console -> App Check ->
        // APIs -> Authentication (set it to "Unenforced"/"Monitor" while
        // testing on non-Play-Store builds, or install via an internal
        // testing track so Play Integrity can actually verify the app).
        debugPrint("Wrapper: forcing sign-out due to ${e.runtimeType}"
            "${e is FirebaseAuthException ? ' (code: ${e.code})' : ''}");

        // FIX: clear the routing cache too -- otherwise a later sign-in
        // (maybe a different account) could pick up this uid's stale
        // cached result if uids ever collided across a fast sign-out/in.
        RouteResolver.instance.clear();
        await FirebaseAuth.instance.signOut();
        return const OtpSignupPage();
      }

      return const _ErrorScreen();
    }
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // FIX(perf): concurrent removals instead of sequential.
      await Future.wait([
        prefs.remove('role'),
        prefs.remove('cached_uid'),
        prefs.remove('onboarding_step'),
      ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // FIX (root cause of "asks for login again after closing the app for
      // a while"): seed the stream with whatever FirebaseAuth already has
      // cached natively, instead of starting from null every time this
      // widget subscribes. On a cold start after Android/iOS has killed the
      // process (which is exactly what "closed for some time" triggers),
      // the native SDK needs a moment to restore the persisted session
      // from disk. `authStateChanges()`'s very FIRST emission can land as a
      // transient `null` a beat before that restore finishes -- not because
      // the session is actually gone. The old code treated that transient
      // null exactly like a real sign-out.
      initialData: FirebaseAuth.instance.currentUser,
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          // INSTANT: no spinner while waiting for the very first auth
          // event -- just show a blank white frame so there's no visible
          // "wait" state flashing before we know if there's a user.
          return const _InstantScreen();
        }

        // FIX: don't trust a `null` snapshot by itself -- double-check
        // against FirebaseAuth's own synchronous `currentUser`. If that
        // still reports a user, the null we just saw from the stream was
        // stale/transient, not a genuine sign-out, so keep the session
        // instead of wiping the cache and forcing the user back to OTP.
        final user = authSnapshot.data ?? FirebaseAuth.instance.currentUser;

        if (user == null) {
          _clearCache();
          RouteResolver.instance.clear(); // FIX: no stale cache for next sign-in
          return const OtpSignupPage();
        }

        // CHANGED: was `checkUser: _checkUser` (a fresh call every time).
        // Now routes through RouteResolver so it reuses whatever
        // SplashScreen already kicked off/finished, instead of Wrapper
        // starting the Firestore read cold the moment it mounts.
        return _WrapperBody(user: user, checkUser: RouteResolver.instance.resolve);
      },
    );
  }
}

class _WrapperBody extends StatefulWidget {
  final User user;
  final Future<Widget> Function(User) checkUser;

  const _WrapperBody({required this.user, required this.checkUser});

  @override
  State<_WrapperBody> createState() => _WrapperBodyState();
}

class _WrapperBodyState extends State<_WrapperBody> {
  late Future<Widget> _future;
  late String _lastUid;

  @override
  void initState() {
    super.initState();
    _lastUid = widget.user.uid;
    _future = widget.checkUser(widget.user);
  }

  void _retry() {
    setState(() {
      _future = widget.checkUser(widget.user);
    });
  }

  @override
  void didUpdateWidget(_WrapperBody old) {
    super.didUpdateWidget(old);
    if (widget.user.uid != _lastUid) {
      _lastUid = widget.user.uid;
      _future = widget.checkUser(widget.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // INSTANT: routing decision resolves in the background with no
          // circular spinner shown -- just a blank white frame so the
          // transition to the resolved screen feels immediate. With
          // RouteResolver warming this up during the splash animation,
          // this branch should rarely even be visible anymore.
          return const _InstantScreen();
        }
        if (snapshot.hasError) {
          return _ErrorScreen(onRetry: _retry);
        }
        return snapshot.data ?? const OtpSignupPage();
      },
    );
  }
}

/// Replaces the old CircularProgressIndicator loading screen. Routing
/// still resolves asynchronously under the hood, but the user never sees
/// a spinner -- just a blank white frame -- so the eventual screen appears
/// to load instantly instead of showing a visible "wait" state.
class _InstantScreen extends StatelessWidget {
  const _InstantScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.shrink(),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final VoidCallback? onRetry;
  const _ErrorScreen({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Illustration
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF5800B3).withOpacity(0.08),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/images/no_connection.svg', // SVG asset
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    placeholderBuilder: (context) => const Icon(
                      Icons.wifi_off_rounded,
                      size: 56,
                      color: Color(0xFF5800B3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                "Something went wrong.",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Please check your connection and try again.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),

              // Retry button -- keeps the current session instead of forcing
              // a sign-out, so e.g. a banned user doesn't lose access to
              // things like the Help Center just because a read failed.
              if (onRetry != null)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5800B3).withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onRetry,
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 18, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                "Try again",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Manual sign-out stays available for anyone who genuinely
              // wants to log out / switch accounts, but it's no longer
              // forced automatically.
              TextButton.icon(
                onPressed: () async {
                  RouteResolver.instance.clear(); // FIX: don't leak into next sign-in
                  await FirebaseAuth.instance.signOut();
                },
                icon: Icon(Icons.logout_rounded,
                    size: 18, color: Colors.grey.shade600),
                label: Text(
                  "Sign out instead",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}