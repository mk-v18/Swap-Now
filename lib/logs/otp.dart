// ignore_for_file: unawaited_futures
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:amoeba/logs/wrapper.dart';
import 'package:amoeba/start/privacy_policy.dart';
import 'package:amoeba/start/terms_of_use.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode + debugPrint
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../start/personal_details.dart';
import 'package:flutter/gestures.dart';

class OtpSignupPage extends StatefulWidget {
  const OtpSignupPage({super.key});

  @override
  State<OtpSignupPage> createState() => _OtpSignupPageState();
}

class _OtpSignupPageState extends State<OtpSignupPage>
    with SingleTickerProviderStateMixin {
  // ── Constants ─────────────────────────────────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _purpleShadow    = Color(0x4D5800B3); // ~30% opacity
  static const _purpleBoxShadow = Color(0x0F5800B3); // ~6%  opacity

  // In debug builds, error snacks show the exact FirebaseAuth/Firestore
  // code + message (handy while testing). In release builds users only
  // ever see the friendly copy from `_friendlyError`. The raw error is
  // ALWAYS logged via debugPrint regardless of build mode, so nothing is
  // lost for reading logs off a release build. Tied to `kDebugMode` so
  // there's no flag to remember to flip before shipping.
  static bool get _showExactErrors => kDebugMode;

  // Network-facing operations get a hard timeout so a slow/stalled
  // connection fails fast with a clear message instead of leaving the
  // user staring at a spinner indefinitely.
  static const Duration _signInTimeout   = Duration(seconds: 15);
  static const Duration _firestoreTimeout = Duration(seconds: 10);

  // Compiled once instead of on every call to _sendOtp / _fillBoxesVisually
  // (each of which can fire multiple times per OTP flow).
  static final RegExp _nonDigits = RegExp(r'\D');

  // ── Firebase ──────────────────────────────────────────────────────────────
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // NOTE: the otp_autofill `OTPInteractor` / SMS User Consent listener was
  // intentionally left out. It registers its own broadcast receiver for the
  // Android `SMS_RETRIEVED` action, and FirebaseAuth.verifyPhoneNumber()
  // already auto-registers its own receiver for that same action internally
  // (that's what powers `verificationCompleted` below). Running both at once
  // let Firebase Auth's closed-source receiver pick up the User-Consent
  // flavored broadcast and crash with a NullPointerException (Consent-API
  // extras where it expected Retriever-API extras). Now that the release
  // SHA-256 fingerprint is registered in the Firebase console, Firebase's
  // built-in SMS Retriever auto-retrieval works on its own —
  // `verificationCompleted` fires automatically with `credential.smsCode`
  // already populated, no permission dialog, no second receiver, no crash.

  // ── Controllers / nodes ───────────────────────────────────────────────────
  final TextEditingController _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
  List.generate(6, (_) => FocusNode());
  final List<FocusNode> _keyListenerNodes =
  List.generate(6, (_) => FocusNode());

  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  // ── OTP state ─────────────────────────────────────────────────────────────
  String _verificationId = '';
  bool   _isSendingOtp   = false;
  bool   _isVerifying    = false;
  bool   _otpSent        = false;
  int?   _resendToken;
  Timer? _resendTimer;

  // ValueNotifier instead of a plain int updated via setState() every
  // second — only the tiny "Resend OTP in Ns" text rebuilds, not the whole
  // page (MediaQuery reads, layout math, hero image, every text widget).
  final ValueNotifier<int> _resendCooldownNotifier = ValueNotifier<int>(0);

  bool _verificationInFlight = false;

  // Single source of truth for the joined code, updated by ONE listener
  // attached to all 6 controllers. Any UI that needs the live code (verify
  // button, "all digits entered" badge) listens to this instead of the
  // whole page rebuilding via setState.
  final ValueNotifier<String> _codeNotifier = ValueNotifier<String>('');

  // Prevents re-triggering verification for the exact same 6-digit code
  // repeatedly (e.g. redundant notifications), while still allowing a
  // fresh attempt if the user edits and re-enters the same digits after a
  // failure (cleared on failure below).
  String _lastAttemptedCode = '';

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _slideCtrl;
  late final Animation<Offset>   _slideAnim;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TermsOfUsePage()),
        );
      };
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
        );
      };

    // Fires no matter HOW a controller's text changed — typed, pasted, or
    // programmatically set via `_fillBoxesVisually` (SMS autofill /
    // platform autofill / paste). Auto-verify works uniformly for every
    // input path instead of being wired separately into each one.
    for (final c in _otpControllers) {
      c.addListener(_onOtpTextChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _otpControllers) c.dispose(); // also removes listeners
    _phoneController.dispose();
    for (final f in _focusNodes)       f.dispose();
    for (final f in _keyListenerNodes) f.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _resendTimer?.cancel();
    _slideCtrl.dispose();
    _codeNotifier.dispose();
    _resendCooldownNotifier.dispose();
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  // ── Centralized OTP-change handler ────────────────────────────────────────
  void _onOtpTextChanged() {
    final code = _otpControllers.map((c) => c.text).join();
    if (code == _codeNotifier.value) return; // nothing actually changed
    _codeNotifier.value = code;

    if (code.length == 6 &&
        !_verificationInFlight &&
        code != _lastAttemptedCode) {
      _lastAttemptedCode = code;
      // Let the current frame (focus/unfocus, box repaint) settle first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _verifyOtp();
      });
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────────
  String _friendlyError(String code) {
    switch (code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP expired. Please request a new one.';
      case 'invalid-phone-number':
        return 'Invalid phone number. Please check and retry.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again after some time.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled. Contact support.';
      case 'app-not-authorized':
      case 'missing-client-identifier':
        return 'This app is not authorized for phone sign-in right now. Please try again later.';
      case 'web-context-cancelled':
        return 'Verification was cancelled. Please try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // Central place that decides what a FirebaseAuth error shows as. Always
  // logs the raw code+message via debugPrint (so it shows up in
  // `flutter run` / `adb logcat` in any build), and returns either the raw
  // text or the friendly copy depending on `_showExactErrors`.
  String _resolveAuthError(FirebaseAuthException e) {
    debugPrint(
        '[OTP][FirebaseAuthException] code=${e.code} message=${e.message} '
            'plugin=${e.plugin}');
    if (_showExactErrors) {
      return '[${e.code}] ${e.message ?? 'no message'}';
    }
    return _friendlyError(e.code);
  }

  // Firestore and other platform failures (e.g. permission-denied,
  // unavailable) don't carry the same `.code` vocabulary as auth errors, so
  // they get a generic — but still logged and still fast to fail — message.
  String _resolveGenericError(Object e, StackTrace st, {required String context}) {
    debugPrint('[OTP][$context] $e\n$st');
    if (_showExactErrors) return 'Error: $e';
    return 'Something went wrong. Please try again.';
  }

  // ── Snack helpers ─────────────────────────────────────────────────────────
  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
        backgroundColor: const Color(0xFF1B8A4C),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin:   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ));
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
        backgroundColor: const Color(0xFFB00020),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin:   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Exact-error messages can run long (code + full Firebase message),
        // so give them more time on screen than the normal 3s.
        duration: Duration(seconds: _showExactErrors ? 6 : 3),
      ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Fill all 6 OTP boxes (SMS autofill / paste). Setting `.value` on a
  /// TextEditingController still notifies listeners, so `_onOtpTextChanged`
  /// fires automatically for each box here — no need to manually trigger
  /// verification afterwards.
  void _fillBoxesVisually(String digits) {
    if (!mounted) return;
    final clean = digits.replaceAll(_nonDigits, '');
    if (clean.length != 6) return;
    for (int i = 0; i < 6; i++) {
      _otpControllers[i].value = TextEditingValue(
        text:      clean[i],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }
    FocusScope.of(context).unfocus();
    TextInput.finishAutofillContext();
  }

  // Ticks a ValueNotifier instead of calling setState() every second.
  // setState() here would rebuild the entire page (MediaQuery lookups,
  // layout math, hero image, all text) once a second for up to 30 seconds
  // straight after every OTP send.
  void _startResendTimer() {
    _resendCooldownNotifier.value = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = _resendCooldownNotifier.value - 1;
      if (next <= 0) {
        t.cancel();
        _resendCooldownNotifier.value = 0;
      } else {
        _resendCooldownNotifier.value = next;
      }
    });
  }

  Future<void> _saveFCMToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(_firestoreTimeout);
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': token})
            .timeout(_firestoreTimeout);
      }
    } catch (e, st) {
      // Non-critical — the user is already signed in at this point, so a
      // failure here should never block or interrupt the sign-in flow.
      // Still logged so a missing token isn't a silent mystery later.
      debugPrint('[OTP][SaveFCMTokenFailed] $e\n$st');
    }
  }

  bool _isValidIndianNumber(String digits) {
    if (digits.length != 10) return false;
    final first = int.tryParse(digits[0]) ?? 0;
    return first >= 6;
  }

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> _sendOtp({bool isResend = false}) async {
    if (_isSendingOtp) return; // guard against double-tap races

    final phone = _phoneController.text.trim().replaceAll(_nonDigits, '');

    if (!_isValidIndianNumber(phone)) {
      _showErrorSnack('Please enter a valid 10-digit Indian mobile number.');
      return;
    }
    if (!mounted) return;
    setState(() => _isSendingOtp = true);

    // verifyPhoneNumber() itself can throw synchronously (e.g. no network,
    // Play Integrity / App Check misconfiguration) before either callback
    // ever fires. Without this try/catch that leaves `_isSendingOtp` stuck
    // `true` forever and the user sees a dead "Continue" button with no
    // explanation.
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber:         '+91$phone',
        forceResendingToken: isResend ? _resendToken : null,
        timeout:             const Duration(seconds: 60),

        // Fires automatically the moment Firebase's own SMS Retriever
        // detects the incoming OTP SMS (release SHA-256 is registered) —
        // no dialog, no extra permission, no second receiver.
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;

          if (!_otpSent) {
            setState(() {
              _otpSent      = true;
              _isSendingOtp = false;
            });
            _slideCtrl.forward();
          } else {
            setState(() => _isSendingOtp = false);
          }

          if (!mounted) return;

          final smsCode = credential.smsCode;
          if (smsCode != null && smsCode.length == 6) {
            // This alone is enough — filling the boxes fires
            // `_onOtpTextChanged` for the 6th box, which schedules
            // `_verifyOtp()` on the next frame. Calling
            // `_signInWithCredential` again immediately after is a no-op
            // (guarded by `_verificationInFlight`), kept only as a
            // fallback in case autofill listener wiring ever changes —
            // no artificial delay needed for either path.
            _fillBoxesVisually(smsCode);
          }

          if (mounted) await _signInWithCredential(credential);
        },

        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
          _showErrorSnack(_resolveAuthError(e));
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken    = resendToken;
            _otpSent        = true;
            _isSendingOtp   = false;
          });
          _slideCtrl.forward();
          _startResendTimer();
          _showSuccessSnack('OTP sent to +91 $phone');
          Future.delayed(
            const Duration(milliseconds: 320), // matches slide-in duration
                () {
              if (mounted) _focusNodes[0].requestFocus();
            },
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      _showErrorSnack(_resolveAuthError(e));
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      _showErrorSnack(_resolveGenericError(e, st, context: 'SendOtpException'));
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    final code = _codeNotifier.value;
    if (code.length < 6) return;

    if (_verificationId.isEmpty) {
      _showErrorSnack('Session expired. Please request a new OTP.');
      return;
    }

    if (_verificationInFlight) return;

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode:        code,
    );
    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    if (!mounted) return;
    if (_verificationInFlight) return;
    _verificationInFlight = true;
    setState(() => _isVerifying = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_signInTimeout);
      final user = userCredential.user;
      if (user == null || !mounted) return;

      // Fire-and-forget — never let a token save delay navigation, and
      // never let it fail the sign-in flow (see try/catch inside).
      _saveFCMToken(user.uid);

      final userRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await userRef.get().timeout(_firestoreTimeout);
      if (!mounted) return;

      if (doc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Wrapper()),
        );
      } else {
        await userRef.set({
          'uid':       user.uid,
          'phone':     user.phoneNumber,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(_firestoreTimeout);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PersonalDetailsPage()),
        );
      }

      _verificationId = '';
    } on FirebaseAuthException catch (e) {
      // Allow retrying the same code after a failure (e.g. user was
      // mid-typing when an auto-verify attempt failed, or wants to
      // resubmit) instead of it being silently blocked forever.
      _lastAttemptedCode = '';
      if (mounted) _showErrorSnack(_resolveAuthError(e));
    } on TimeoutException catch (e, st) {
      _lastAttemptedCode = '';
      debugPrint('[OTP][TimeoutException] $e\n$st');
      if (mounted) {
        _showErrorSnack(_showExactErrors
            ? 'Timeout: $e'
            : 'This is taking longer than expected. Please check your connection and try again.');
      }
    } on FirebaseException catch (e, st) {
      // Firestore-specific failures (permission-denied, unavailable,
      // etc.) — distinct from auth failures so the log makes it obvious
      // which layer broke.
      _lastAttemptedCode = '';
      debugPrint('[OTP][FirestoreException] code=${e.code} message=${e.message}');
      if (mounted) {
        _showErrorSnack(_showExactErrors
            ? '[${e.code}] ${e.message ?? 'no message'}'
            : 'Signed in, but we could not finish setting up your account. Please try again.');
      }
    } catch (e, st) {
      _lastAttemptedCode = '';
      if (mounted) {
        _showErrorSnack(_resolveGenericError(e, st, context: 'UnhandledException'));
      }
    } finally {
      _verificationInFlight = false;
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _resendOtp() async {
    if (_resendCooldownNotifier.value > 0) return;
    for (final c in _otpControllers) c.clear();
    _lastAttemptedCode = '';
    _focusNodes[0].requestFocus();
    await _sendOtp(isResend: true);
  }

  // ── Back to phone screen ──────────────────────────────────────────────────
  void _goBackToPhone() {
    _resendTimer?.cancel();
    _resendCooldownNotifier.value = 0;

    _slideCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _otpSent = false);
      for (final c in _otpControllers) c.clear();
      _lastAttemptedCode = '';
    });
  }

  // ── OTP box widget ────────────────────────────────────────────────────────
  // Wrapped in AnimatedBuilder listening ONLY to this box's own controller.
  // Typing a digit only rebuilds this one small widget, instead of
  // setState() rebuilding the entire page on every keystroke.
  Widget _buildOtpBox(int index, double boxSize) {
    return SizedBox(
      width:  boxSize,
      height: boxSize * 1.15,
      child: AnimatedBuilder(
        animation: _otpControllers[index],
        builder: (context, _) {
          final isFilled = _otpControllers[index].text.isNotEmpty;
          return KeyboardListener(
            focusNode: _keyListenerNodes[index],
            onKeyEvent: (KeyEvent event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.backspace) {
                if (_otpControllers[index].text.isEmpty && index > 0) {
                  _otpControllers[index - 1].clear();
                  _focusNodes[index - 1].requestFocus();
                }
              }
            },
            child: TextField(
              controller:      _otpControllers[index],
              focusNode:       _focusNodes[index],
              keyboardType:    TextInputType.number,
              textAlign:       TextAlign.center,
              maxLength:       1,
              autofillHints:   const [AutofillHints.oneTimeCode],
              textInputAction:
              index < 5 ? TextInputAction.next : TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize:   boxSize * 0.30,
                fontWeight: FontWeight.w600,
                color:      Colors.black,
              ),
              decoration: InputDecoration(
                counterText:    '',
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  const BorderSide(color: Color(0xFFDDD6F0), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _purple, width: 2),
                ),
                filled:    true,
                fillColor: isFilled
                    ? const Color(0xFFF5F0FF)
                    : Colors.white,
              ),
              // onChanged ONLY handles focus movement and paste
              // distribution — nothing else. Fill color is handled above
              // via AnimatedBuilder, and auto-verify is handled centrally
              // by `_onOtpTextChanged`, so this can never get out of sync
              // with what the controllers actually contain.
              onChanged: (value) {
                if (value.length > 1) {
                  final digits = value.replaceAll(_nonDigits, '');
                  if (digits.length == 6) {
                    _fillBoxesVisually(digits);
                    return;
                  }
                  _otpControllers[index].value = TextEditingValue(
                    text:      value[0],
                    selection: const TextSelection.collapsed(offset: 1),
                  );
                }

                if (value.isEmpty) {
                  if (index > 0 && _otpControllers[index - 1].text.isNotEmpty) {
                    _focusNodes[index - 1].requestFocus();
                  }
                } else {
                  if (index < 5) {
                    _focusNodes[index + 1].requestFocus();
                  } else {
                    FocusScope.of(context).unfocus();
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Split MediaQuery.of(context) into scoped aspect accessors.
    // MediaQuery.of() ties this whole build() to EVERY MediaQuery field
    // (size, viewInsets, padding, textScale, gestureSettings, ...), so any
    // unrelated change (e.g. system text-scale, a padding tweak from a
    // status-bar animation) would rebuild this whole page. The `*Of()`
    // accessors scope the dependency to just that one field.
    final screenSize        = MediaQuery.sizeOf(context);
    final screenW           = screenSize.width;
    final screenH           = screenSize.height;
    final viewInsetsBottom  = MediaQuery.viewInsetsOf(context).bottom;

    final hPad  = screenW < 380 ? 16.0 : 22.0;
    final heroH = screenH < 680
        ? screenH * 0.20
        : screenH < 780
        ? screenH * 0.22
        : 180.0;

    final otpTotalW = screenW - hPad * 2;
    final rawBoxW   = (otpTotalW - 5 * 8) / 6;
    final boxSize   = rawBoxW.clamp(36.0, 52.0);

    // Verification progress stays anchored to the Verify button's own
    // inline spinner (`isLoading: _isVerifying`, see `_PurpleButton`)
    // rather than swapping out the whole page for a full-screen spinner —
    // the OTP boxes the user just filled in shouldn't visibly vanish while
    // sign-in + the Firestore user-doc lookup are in flight.
    return Scaffold(
      backgroundColor:Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: screenH * 0.03),

                    Center(
                      child: Image.asset(
                        'assets/images/signup-image.png',
                        height: heroH,
                        fit: BoxFit.contain,
                      ),
                    ),

                    SizedBox(height: screenH * 0.032),

                    // ── PHONE SCREEN ────────────────────────────────────────
                    if (!_otpSent) ...[
                      RichText(
                        text: const TextSpan(
                          text:  'Welcome to ',
                          style: TextStyle(
                              color:      Colors.black,
                              fontSize:   26,
                              fontWeight: FontWeight.w800,
                              height:     1.2),
                          children: [
                            TextSpan(
                              text:  'Amoeba',
                              style: TextStyle(color: _purple),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Enter your mobile number to begin your journey',
                        style: TextStyle(
                            fontSize:   13,
                            fontWeight: FontWeight.w400,
                            color:      Colors.grey),
                      ),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border:
                          Border.all(color: _purple, width: 1.5),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color:      _purpleBoxShadow,
                              blurRadius: 12,
                              offset:     Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color:        const Color(0xFFF5F0FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🇮🇳',
                                      style: TextStyle(fontSize: 16)),
                                  SizedBox(width: 4),
                                  Text('+91',
                                      style: TextStyle(
                                          fontSize:   15,
                                          fontWeight: FontWeight.w600,
                                          color:      _purple)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                                width: 1,
                                height: 28,
                                color: const Color(0xFFEEE8F8)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller:      _phoneController,
                                keyboardType:    TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                autofocus:       true,
                                onSubmitted:     (_) =>
                                _isSendingOtp ? null : _sendOtp(),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                // No setState() here — the Continue button
                                // below listens to this controller directly
                                // via AnimatedBuilder.
                                style: const TextStyle(
                                    fontSize:      16,
                                    fontWeight:    FontWeight.w500,
                                    letterSpacing: 1.2),
                                decoration: const InputDecoration(
                                  border:    InputBorder.none,
                                  hintText:  'Mobile number',
                                  hintStyle: TextStyle(
                                      fontSize:      15,
                                      fontWeight:    FontWeight.w400,
                                      color:         Color(0xFFBBB3CC),
                                      letterSpacing: 0),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Only this button rebuilds as the phone number is
                      // typed, via AnimatedBuilder on _phoneController —
                      // not the whole page.
                      AnimatedBuilder(
                        animation: _phoneController,
                        builder: (context, _) => _PurpleButton(
                          label:     'Continue',
                          isLoading: _isSendingOtp,
                          enabled:   _phoneController.text.length == 10,
                          onTap:     _isSendingOtp ? null : _sendOtp,
                        ),
                      ),
                    ],

                    // ── OTP SCREEN ──────────────────────────────────────────
                    if (_otpSent)
                      SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _goBackToPhone,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_ios_new_rounded,
                                      size: 16, color: _purple),
                                  SizedBox(width: 4),
                                  Text('Change number',
                                      style: TextStyle(
                                          fontSize:   13,
                                          color:      _purple,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            RichText(
                              text: const TextSpan(
                                text:  'Enter ',
                                style: TextStyle(
                                    color:      Colors.black,
                                    fontSize:   26,
                                    fontWeight: FontWeight.w800,
                                    height:     1.2),
                                children: [
                                  TextSpan(
                                    text:  'OTP',
                                    style: TextStyle(color: _purple),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                    fontSize:   13,
                                    color:      Colors.grey,
                                    fontWeight: FontWeight.w400),
                                children: [
                                  const TextSpan(text: 'Sent to '),
                                  TextSpan(
                                    text: '+91 ${_phoneController.text.trim()}',
                                    style: const TextStyle(
                                        color:      Colors.black87,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            // OTP boxes are disabled (not editable) while
                            // verification is in flight, so a user can't
                            // keep editing digits while a sign-in request
                            // for the previous code is still in the air.
                            AbsorbPointer(
                              absorbing: _isVerifying,
                              child: AutofillGroup(
                                child: Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: List.generate(
                                      6, (i) => _buildOtpBox(i, boxSize)),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Only this small badge rebuilds as digits are
                            // entered, via ValueListenableBuilder on
                            // _codeNotifier.
                            ValueListenableBuilder<String>(
                              valueListenable: _codeNotifier,
                              builder: (context, code, _) => AnimatedOpacity(
                                opacity:  code.length == 6 ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 14, color: Color(0xFF1B8A4C)),
                                      SizedBox(width: 4),
                                      Text('All digits entered',
                                          style: TextStyle(
                                              fontSize:   12,
                                              color:      Color(0xFF1B8A4C),
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            ValueListenableBuilder<String>(
                              valueListenable: _codeNotifier,
                              builder: (context, code, _) => _PurpleButton(
                                label:     'Verify',
                                isLoading: _isVerifying,
                                enabled:   code.length == 6,
                                onTap:     _isVerifying ? null : _verifyOtp,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Isolated to just this small
                            // ValueListenableBuilder instead of rebuilding
                            // the whole page every second.
                            Center(
                              child: _isSendingOtp
                                  ? const SizedBox(
                                width:  18,
                                height: 18,
                                child:  CircularProgressIndicator(
                                    color:       _purple,
                                    strokeWidth: 2),
                              )
                                  : ValueListenableBuilder<int>(
                                valueListenable: _resendCooldownNotifier,
                                builder: (context, cooldown, _) {
                                  if (cooldown > 0) {
                                    return RichText(
                                      text: TextSpan(
                                        text:  'Resend OTP in ',
                                        style: const TextStyle(
                                            color:      Colors.grey,
                                            fontSize:   13,
                                            fontWeight: FontWeight.w500),
                                        children: [
                                          TextSpan(
                                            text: '${cooldown}s',
                                            style: const TextStyle(
                                                color:      _purple,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return GestureDetector(
                                    onTap: _resendOtp,
                                    child: const Text(
                                      'Resend OTP',
                                      style: TextStyle(
                                        decoration:
                                        TextDecoration.underline,
                                        color:      _purple,
                                        fontWeight: FontWeight.w600,
                                        fontSize:   14,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // ── FIXED TERMS ─────────────────────────────────────────────────
            if (viewInsetsBottom == 0)
              Padding(
                padding:
                const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 11.5, height: 1.5),
                    children: [
                      const TextSpan(text: 'By continuing, you agree to our '),
                      TextSpan(
                        text:       'Terms of Use',
                        style:      const TextStyle(
                            color:      _purple,
                            decoration: TextDecoration.underline),
                        recognizer: _termsRecognizer,
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text:       'Privacy Policy',
                        style:      const TextStyle(
                            color:      _purple,
                            decoration: TextDecoration.underline),
                        recognizer: _privacyRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable purple CTA button ──────────────────────────────────────────────
class _PurpleButton extends StatelessWidget {
  final String        label;
  final bool          isLoading;
  final bool          enabled;
  final VoidCallback? onTap;

  const _PurpleButton({
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.onTap,
  });

  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _shadowColor = Color(0x4D5800B3); // purple @ 30%

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 150),
        width:     double.infinity,
        padding:   const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: [_purple, _deepPurple])
              : null,
          color:        enabled ? null : const Color(0xFFE8E2F4),
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? const [
            BoxShadow(
              color:      _shadowColor,
              blurRadius: 14,
              offset:     Offset(0, 6),
            ),
          ]
              : null,
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
          width:  22,
          height: 22,
          child:  CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2),
        )
            : Text(
          label,
          style: TextStyle(
            color:         enabled ? Colors.white : const Color(0xFFAA99CC),
            fontSize:      16,
            fontWeight:    FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}