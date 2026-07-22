import 'package:credbro/logs/banned_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin panel/admin_bottom_nav.dart';
import '../start/payment.dart';
import '../start/starting_page.dart';
import 'otp.dart';
import '../pages/bottom_navigation.dart';
import '../start/personal_details.dart';


class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  /// Errors that genuinely mean "this session is no longer valid" — only
  /// these should force a sign-out. Everything else (permission-denied from
  /// Firestore rules, network hiccups, timeouts, etc.) must NOT sign the
  /// user out — it should just show a retryable error screen. This matters
  /// a lot for banned users: if your Firestore rules deny reads based on a
  /// `banned` field, that throws a `permission-denied` FirebaseException,
  /// which used to be caught here and treated as a reason to sign out —
  /// silently kicking banned users out of their own session (and breaking
  /// things like the in-app Help Center, which needs `currentUser` to stay
  /// non-null).
  bool _isSessionInvalid(Object error) {
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

  Future<Widget> _checkUser(User user) async {
    try {
      // FIX(perf): Kick off the SharedPreferences load and the Firestore
      // read at the same time instead of awaiting them one after another.
      // They don't depend on each other — the old code paid for two full
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
        // FIX(perf): three independent key removals — run them concurrently
        // instead of three sequential awaits.
        await Future.wait([
          prefs.remove('role'),
          prefs.remove('cached_uid'),
          prefs.remove('onboarding_step'),
        ]);
      }

      // NOTE: we intentionally do NOT short-circuit on a cached role here
      // anymore. Role can be changed out-of-band (e.g. an admin flips a
      // user's `role` field directly in the Firestore console), and a
      // cached-role fast path would keep routing the user based on stale
      // data until the cache was manually cleared — which is exactly the
      // bug that caused a Firestore-promoted admin to keep landing on the
      // regular BottomNavigation instead of AdminBottomNavigation. Role
      // must always come from a fresh Firestore read.

      if (!doc.exists) return const PersonalDetailsPage();

      final data = doc.data() ?? {};
      final role = data['role']?.toString().trim().toLowerCase() ?? 'user';
      final hasPaid = data['hasPaid'] == true;
      final name = data['name']?.toString().trim() ?? '';
      final email = data['email']?.toString().trim() ?? '';
      final location = data['location']?.toString().trim() ?? '';
      final image = data['profileImage']?.toString().trim() ?? '';
      // Checkpoint written by each onboarding step:
      // 'personal_details' -> 'payment' -> 'starting_page' -> 'done'
      final step =
          data['onboardingStep']?.toString().trim() ?? 'personal_details';

      // Admins skip the consumer onboarding flow entirely.
      if (role == 'admin') {
        // FIX(perf): three independent writes — fire together, await once.
        await Future.wait([
          prefs.setString('role', role),
          prefs.setString('cached_uid', user.uid),
          prefs.setString('onboarding_step', 'done'),
        ]);
        return const AdminBottomNavigation();
      }

      final profileComplete = name.isNotEmpty &&
          email.isNotEmpty &&
          location.isNotEmpty &&
          image.isNotEmpty;

      // Resume exactly where the user left off:
      if (!profileComplete) return const PersonalDetailsPage();
      if (!hasPaid) return const PaymentPage();
      if (step != 'done') return const StartingPage();

      // FIX(perf): same three-writes-in-parallel treatment here.
      await Future.wait([
        prefs.setString('role', role),
        prefs.setString('cached_uid', user.uid),
        prefs.setString('onboarding_step', 'done'),
      ]);
      return BannedGate(uid: user.uid, child: const BottomNavigation());
    } catch (e) {
      debugPrint("Wrapper error: $e");

      // Only sign out for errors that mean the session itself is actually
      // invalid. Everything else (e.g. Firestore permission-denied for a
      // banned user, transient network failures) should NOT sign the user
      // out — show a retryable error screen instead so they keep their
      // session (and can still reach things like the banned-account page
      // or Help Center).
      if (_isSessionInvalid(e)) {
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
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        if (!authSnapshot.hasData) {
          _clearCache();
          return const OtpSignupPage();
        }
        final user = authSnapshot.data!;

        // StatefulWidget caches the future so FutureBuilder never reruns it
        // unless the user's UID actually changes — prevents repeated
        // Firestore reads / screen flicker on unrelated auth stream events.
        return _WrapperBody(user: user, checkUser: _checkUser);
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
          return const _LoadingScreen();
        }
        if (snapshot.hasError) {
          return _ErrorScreen(onRetry: _retry);
        }
        return snapshot.data ?? const OtpSignupPage();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF5800B3)),
      ),
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
                  child: Image.asset(
                    'assets/images/no_connection.png', // swap in your asset
                    width: 80,
                    height: 80,
                    errorBuilder: (context, error, stackTrace) => const Icon(
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

              // Retry button — keeps the current session instead of forcing
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