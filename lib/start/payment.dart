import 'dart:async';

import 'package:credbro/start/payment_fail.dart';
import 'package:credbro/start/payment_success.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ── Key handling ────────────────────────────────────────────────────────────
// The Razorpay `key_id` is a *publishable* key — Razorpay's own checkout flow
// expects it embedded client-side, so this isn't a secret the way an AES key
// or Razorpay `key_secret` would be. Moving it to Remote Config buys you two
// things a hardcoded const can't:
//   1. Swap test → live key (or rotate a compromised one) without an app
//      store release.
//   2. One flag, all installed devices pick it up next fetch.
//
// A hardcoded fallback is kept ONLY for the case where Remote Config is
// unreachable (first launch, offline, etc.) — set this to your current
// test key so behavior is unchanged if the fetch fails.
const String _kRazorpayKeyFallback = 'rzp_test_TBJCKQmpFKyNl6'; // TODO: paste your regenerated test key_id
const int _kAmountPaise = 9900; // ₹99.00

// If the Razorpay checkout sheet is dismissed/killed without firing any
// callback (app backgrounded, OS reclaims process, etc.), this timeout
// resets the "processing" UI so the user isn't stuck with a disabled button.
const Duration _kProcessingTimeout = Duration(seconds: 90);

// ── Responsive helper ──────────────────────────────────────────────────────
class _Resp {
  final double w;
  final double h;
  final bool isSmall; // < 360 dp wide  (Galaxy A series, etc.)
  final bool isLarge; // > 600 dp wide  (tablets, foldables)

  const _Resp({
    required this.w,
    required this.h,
    required this.isSmall,
    required this.isLarge,
  });

  // FIX(perf): MediaQuery.sizeOf() instead of MediaQuery.of().size — scopes
  // the InheritedWidget dependency to just the `size` aspect, so unrelated
  // MediaQuery changes (text scale, padding, etc.) don't trigger a rebuild.
  factory _Resp.of(BuildContext ctx) {
    final s = MediaQuery.sizeOf(ctx);
    return _Resp(
      w: s.width,
      h: s.height,
      isSmall: s.width < 360,
      isLarge: s.width >= 600,
    );
  }

  // clamp a fraction of screen width between [min] and [max] dp
  double wf(double frac, {double min = 0, double max = double.infinity}) =>
      (w * frac).clamp(min, max);

  // clamp a fraction of screen height
  double hf(double frac, {double min = 0, double max = double.infinity}) =>
      (h * frac).clamp(min, max);

  double get hPad => isLarge ? 32 : 18;
  double get titleSize => isSmall ? 20 : (isLarge ? 30 : 24);
  double get bodySize => isSmall ? 14 : (isLarge ? 18 : 16);
  double get featureSize => isSmall ? 14 : (isLarge ? 18 : 16);
  double get btnHeight => isSmall ? 50 : (isLarge ? 64 : 56);
  double get btnRadius => isLarge ? 18 : 14;
  double get iconSize => isSmall ? 18 : (isLarge ? 24 : 20);
}

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage>
    with SingleTickerProviderStateMixin {
  late final Razorpay _razorpay;

  // FIX(perf): isolated into a ValueNotifier — see build() below. Flipping
  // this used to rebuild the ENTIRE page (background image, SVG
  // illustration, feature list, everything) just to swap the CTA button
  // between "Get Started" and a spinner.
  final ValueNotifier<bool> _isProcessingNotifier = ValueNotifier<bool>(false);

  Timer? _processingTimeoutTimer;

  // Resolved once in initState — either the Remote Config value or the
  // hardcoded fallback. Never read _kRazorpayKeyFallback directly elsewhere.
  // FIX(perf/bug): plain field, no setState — nothing in build() reads this
  // value (it's only used later inside _openCheckout), so wrapping its
  // assignment in setState was rebuilding the whole page for zero visual
  // change every time Remote Config resolved.
  String _razorpayKey = _kRazorpayKeyFallback;

  // Initialized in initState — AnimationController requires vsync (this),
  // which is only valid after the mixin is attached, so late is correct here.
  // We guard build() with a null-aware fallback to prevent any premature access.
  AnimationController? _fadeCtrl;
  Animation<double>? _fadeAnim;

  @override
  void initState() {
    super.initState();

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    // Safe to use `this` as vsync now that super.initState() has run.
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl!, curve: Curves.easeOut);
    _fadeCtrl!.forward();

    _loadRazorpayKey();
  }

  // Fetches the key_id from Remote Config. Falls back silently to the
  // hardcoded test key on any failure — checkout must never be blocked by
  // a Remote Config outage.
  Future<void> _loadRazorpayKey() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await remoteConfig.setDefaults({'razorpay_key_id': _kRazorpayKeyFallback});
      await remoteConfig.fetchAndActivate();

      final fetched = remoteConfig.getString('razorpay_key_id');
      if (fetched.isNotEmpty && mounted) {
        // FIX(perf/bug): no setState — this value isn't read by build().
        _razorpayKey = fetched;
      }
    } catch (e) {
      debugPrint('Remote Config fetch failed, using fallback key: $e');
      // _razorpayKey already holds the fallback — nothing else to do.
    }
  }

  @override
  void dispose() {
    _processingTimeoutTimer?.cancel();
    _razorpay.clear();
    _fadeCtrl?.dispose();
    _isProcessingNotifier.dispose();
    super.dispose();
  }

  // ── Snackbar helpers ───────────────────────────────────────────────────────

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFB00020),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.only(top: 50, left: 16, right: 16),
          dismissDirection: DismissDirection.up,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1B8A4C),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.only(top: 50, left: 16, right: 16),
          dismissDirection: DismissDirection.up,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Processing-state helpers ──────────────────────────────────────────────

  void _startProcessing() {
    if (!mounted) return;
    _isProcessingNotifier.value = true;

    // Safety net: if no Razorpay callback ever fires (process killed,
    // checkout sheet dismissed without an event, etc.), unstick the UI.
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = Timer(_kProcessingTimeout, () {
      if (!mounted) return;
      if (_isProcessingNotifier.value) {
        _isProcessingNotifier.value = false;
        _showErrorSnack("Payment timed out. Please try again.");
      }
    });
  }

  void _stopProcessing() {
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = null;
    if (mounted) _isProcessingNotifier.value = false;
  }

  // FIX(bug): New helper — cancels the safety-net timeout WITHOUT clearing
  // _isProcessing. Used at the top of _handlePaymentSuccess so the timeout
  // can't misfire mid-verification, while the spinner correctly stays up
  // for the full duration of the server-side verifyPayment call instead of
  // flashing back to an idle "Get Started" button first.
  void _cancelProcessingTimeoutOnly() {
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = null;
  }

  // ── Payment ────────────────────────────────────────────────────────────────
  //
  // ✅ FIX: Razorpay's `razorpay_signature` is only meaningful when checkout
  // was opened against a real server-created Order (`order_id`). Previously
  // this method opened checkout WITHOUT an order_id, so Razorpay could never
  // return a signature that would match verifyPayment's
  // HMAC(orderId + "|" + paymentId, secret) check — verification failed
  // 100% of the time, even with correct test keys.
  //
  // Fix: call the new `createRazorpayOrder` Cloud Function first to get a
  // real order_id from Razorpay's Orders API, then pass that into checkout.
  Future<void> _openCheckout() async {
    if (_isProcessingNotifier.value) return; // guard against double-tap

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorSnack("Session expired. Please log in again.");
      return;
    }

    _startProcessing();

    String orderId;
    try {
      final callable =
      FirebaseFunctions.instance.httpsCallable('createRazorpayOrder');
      final result = await callable.call().timeout(const Duration(seconds: 15));
      final data = result.data as Map;
      orderId = data['orderId'] as String;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('createRazorpayOrder rejected: ${e.code} ${e.message}');
      _stopProcessing();
      _showErrorSnack("Could not start payment. Please try again.");
      return;
    } catch (e) {
      debugPrint('createRazorpayOrder call error: $e');
      _stopProcessing();
      _showErrorSnack("Network error. Please check your connection and retry.");
      return;
    }

    final options = {
      'key': _razorpayKey,
      'amount': _kAmountPaise,
      'order_id': orderId, // ✅ required for a valid signature to be returned
      'name': 'swapnow',
      'description': 'Registration Fee — Lifetime Access',
      'prefill': {'contact': user.phoneNumber ?? ''},
      'external': {
        'wallets': ['paytm']
      },
      'method': {
        'upi': true,
        'card': true,
        'netbanking': true,
        'wallet': true,
      },
      'theme': {'color': '#5800B3'},
      'notes': {'uid': user.uid},
    };

    try {
      _razorpay.open(options);
      // _isProcessing is already true from _startProcessing() above — the
      // timeout timer set there still applies while the checkout sheet is open.
    } catch (e) {
      debugPrint('Razorpay open error: $e');
      _stopProcessing();
      _showErrorSnack("Could not open payment. Please try again.");
    }
  }

  // ✅ SECURITY NOTE:
  // `hasPaid` is now flipped ONLY by the `verifyPayment` Cloud Function,
  // after it verifies the HMAC-SHA256 signature server-side. This client
  // code never writes `hasPaid` directly — it just logs the raw payment
  // attempt (for your own records/support lookups) and asks the server to
  // verify + grant access. Even if someone tampers with this Dart code or
  // calls Firestore directly, they can't grant themselves access without
  // passing verifyPayment's signature check.
  //
  // ✅ FIX(bug): This used to call _stopProcessing() as the very first line,
  // which immediately flipped the button back to its idle "Get Started"
  // state — while the server-side verifyPayment call (which can take
  // several seconds) was still in flight. That's the "goes back to the
  // payment page for a few seconds, then jumps to success" bug: the app
  // genuinely was showing the idle payment page while waiting on
  // verification. Now the spinner stays up for the whole verify call —
  // only the timeout timer is cancelled up front — and _isProcessing is
  // only cleared in the failure branches (on success the page is replaced
  // entirely, so there's nothing to reset).
  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    _cancelProcessingTimeoutOnly();
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _stopProcessing();
      _showErrorSnack("Session expired. Contact support with payment ID.");
      return;
    }

    final paymentId = response.paymentId ?? 'unknown';
    final orderId = response.orderId ?? '';
    final signature = response.signature ?? '';
    final now = DateTime.now();

    // 1. Log the raw attempt — for support/records only, does NOT grant
    //    access by itself. Wrapped separately so a logging failure never
    //    blocks the actual verification call below.
    try {
      await FirebaseFirestore.instance.collection('payments').add({
        'userId': user.uid,
        'phone': user.phoneNumber ?? '',
        'paymentId': paymentId,
        'orderId': orderId,
        'signature': signature,
        'amount': _kAmountPaise,
        'currency': 'INR',
        'status': 'pending_verification',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Non-fatal: failed to log payment attempt: $e');
    }

    // 2. Ask the server to verify the signature and grant access.
    //    onboardingStep is advanced to 'starting_page' server-side (not
    //    'done') so that if the user closes the app right after paying,
    //    Wrapper resumes them on StartingPage instead of dropping them
    //    straight into the home shell.
    try {
      final callable =
      FirebaseFunctions.instance.httpsCallable('verifyPayment');
      final result = await callable.call({
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      }).timeout(const Duration(seconds: 15));

      final verified = (result.data as Map)['verified'] == true;
      if (!verified) {
        throw Exception('Server did not confirm verification.');
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            paymentId: paymentId,
            time: now.toIso8601String(),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('verifyPayment rejected: ${e.code} ${e.message}');
      _stopProcessing();
      if (!mounted) return;
      // Payment went through on Razorpay's side but server verification
      // failed or the signature didn't match — don't grant access, and
      // don't tell the user it succeeded. Send them to support instead of
      // the failure page, since money may have actually moved.
      _showErrorSnack(
          "Payment received but verification failed. Contact support with "
              "payment ID: $paymentId");
    } catch (e) {
      debugPrint('verifyPayment call error: $e');
      _stopProcessing();
      if (!mounted) return;
      // Network/timeout — payment likely succeeded but we couldn't confirm.
      // Same reasoning: don't show success, don't lose the payment ID.
      _showErrorSnack(
          "Couldn't confirm payment right now. Contact support with "
              "payment ID: $paymentId if this persists.");
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) async {
    _stopProcessing();
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final code = response.code ?? 0;
    final message = response.message ?? 'Unknown error';

    // TEMP DEBUG — remove once root cause is confirmed.
    debugPrint('Razorpay payment error — code: $code, message: $message');
    debugPrint('Razorpay error details: ${response.error}');

    try {
      await FirebaseFirestore.instance.collection('payments').add({
        'userId': user?.uid ?? 'unknown',
        'phone': user?.phoneNumber ?? '',
        'code': code,
        'message': message,
        'status': 'failed',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to log payment error: $e');
    }

    // Note: hasPaid / onboardingStep are intentionally left untouched here.
    // On relaunch, Wrapper sees hasPaid == false and correctly sends the
    // user back to PaymentPage — no separate "failed" checkpoint needed.
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentFailedPage(
          errorCode: code.toString(),
          errorMessage: _friendlyPaymentError(code, message),
        ),
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _stopProcessing();
    if (!mounted) return;
    _showSuccessSnack("Redirecting to ${response.walletName ?? 'wallet'}...");
  }

  String _friendlyPaymentError(int? code, String rawMessage) {
    switch (code) {
      case Razorpay.PAYMENT_CANCELLED:
        return "Payment was cancelled. You can try again anytime.";
      case Razorpay.NETWORK_ERROR:
        return "Network error. Please check your connection and retry.";
      case Razorpay.INVALID_OPTIONS:
        return "Payment could not be initiated. Please contact support.";
      default:
        return "Payment failed. Please try a different payment method.";
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final r = _Resp.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.white),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim ?? const AlwaysStoppedAnimation(1.0),
              child: Center(
                // ✅ Caps max width on tablets/large screens
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: r.hPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: r.hf(0.05, min: 16, max: 48)),

                        // ── Title ──────────────────────────────────────────
                        Text(
                          "Registration Fee",
                          style: TextStyle(
                            fontSize: r.titleSize,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: -0.3,
                          ),
                        ),

                        SizedBox(height: r.hf(0.015, min: 8, max: 20)),

                        // ── Illustration ───────────────────────────────────
                        SizedBox(
                          width: r.wf(0.34, min: 100, max: 180),
                          height: r.wf(0.34, min: 100, max: 180),
                          child: SvgPicture.asset(
                            'assets/images/price_details.svg',
                            fit: BoxFit.contain,
                          ),
                        ),

                        SizedBox(height: r.hf(0.018, min: 8, max: 20)),

                        // ── Lifetime Access badge ──────────────────────────
                        OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF5800B3),
                            side: const BorderSide(
                                color: Color(0xFF5800B3), width: 1.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: r.wf(0.07, min: 20, max: 48),
                              vertical: r.hf(0.012, min: 8, max: 14),
                            ),
                          ),
                          child: Text(
                            'Lifetime Access',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: r.bodySize - 1,
                              color: const Color(0xFF5800B3),
                            ),
                          ),
                        ),

                        SizedBox(height: r.hf(0.045, min: 12, max: 32)),

                        // ── Features list ──────────────────────────────────
                        // FIX(perf): pass the already-computed `r` down
                        // instead of each _FeatureLabel calling _Resp.of()
                        // (and therefore MediaQuery.sizeOf()) independently
                        // — that was 6 redundant lookups + object
                        // constructions on every single build.
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              _FeatureLabel("Unlimited access to features", r),
                              _FeatureLabel("Priority customer support", r),
                              _FeatureLabel("All updates included", r),
                              _FeatureLabel(
                                  "One-time payment, no hidden charges", r),
                              _FeatureLabel("Instant account activation", r),
                              _FeatureLabel(
                                  "Secure & encrypted transactions", r),
                            ],
                          ),
                        ),

                        SizedBox(height: r.hf(0.015, min: 8, max: 20)),

                        // ── CTA button ─────────────────────────────────────
                        // FIX(perf): isolated to _isProcessingNotifier — only
                        // this button rebuilds when payment starts/stops
                        // processing, not the background, illustration, or
                        // feature list.
                        ValueListenableBuilder<bool>(
                          valueListenable: _isProcessingNotifier,
                          builder: (context, isProcessing, _) => SizedBox(
                            width: double.infinity,
                            height: r.btnHeight,
                            child: ElevatedButton(
                              onPressed: isProcessing ? null : _openCheckout,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(r.btnRadius),
                                ),
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                elevation: 0,
                              ),
                              child: Ink(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF5800B3),
                                      Color(0xFF26004D),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius:
                                  BorderRadius.circular(r.btnRadius),
                                  boxShadow: isProcessing
                                      ? null
                                      : const [
                                    BoxShadow(
                                      // FIX(perf): pre-computed constant
                                      // colour — no withOpacity()
                                      // allocation on every build.
                                      color: Color(0x595800B3),
                                      blurRadius: 14,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  alignment: Alignment.center,
                                  child: isProcessing
                                      ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "Get Started",
                                        style: TextStyle(
                                          fontSize: r.bodySize,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: r.hf(0.018, min: 10, max: 20)),

                        // ── Security badge ─────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 13, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              "Secured by Razorpay",
                              style: TextStyle(
                                fontSize: r.isSmall ? 10 : 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: r.hf(0.03, min: 12, max: 32)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature row ──────────────────────────────────────────────────────────
// FIX(perf): Now takes the parent's already-computed `_Resp` instead of
// calling `_Resp.of(context)` (MediaQuery.sizeOf + object construction)
// independently for each of the 6 rows on every build.
class _FeatureLabel extends StatelessWidget {
  const _FeatureLabel(this.text, this.r);

  final String text;
  final _Resp r;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.isSmall ? 7 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/icons/check.svg',
            width: r.iconSize,
            height: r.iconSize,
            colorFilter: const ColorFilter.mode(
              Color(0xFF4A0D9E),
              BlendMode.srcIn,
            ),
          ),
          SizedBox(width: r.isSmall ? 8 : 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: r.featureSize,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}