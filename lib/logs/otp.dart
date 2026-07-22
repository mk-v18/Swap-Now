// ignore_for_file: unawaited_futures
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/logs/wrapper.dart';
import 'package:credbro/start/privacy_policy.dart';
import 'package:credbro/start/terms_of_use.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

  // FIX(perf): compiled once instead of on every call to _sendOtp /
  // _fillBoxesVisually (each of which can fire multiple times per OTP flow).
  static final RegExp _nonDigits = RegExp(r'\D');

  // ── Firebase ──────────────────────────────────────────────────────────────
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  // FIX(perf): This used to be a plain int updated via setState() every
  // second from the resend-cooldown Timer, which reran the ENTIRE page
  // build() (MediaQuery reads, layout math, hero image, every text widget)
  // once a second for up to 30 seconds after every OTP send. Now it's a
  // ValueNotifier so only the tiny "Resend OTP in Ns" text rebuilds.
  final ValueNotifier<int> _resendCooldownNotifier = ValueNotifier<int>(0);

  bool _verificationInFlight = false;

  // FIX(reliability + perf): Single source of truth for the joined code,
  // updated by ONE listener attached to all 6 controllers. Any UI that needs
  // the live code (verify button, "all digits entered" badge) listens to
  // this instead of the whole page rebuilding via setState.
  final ValueNotifier<String> _codeNotifier = ValueNotifier<String>('');

  // FIX(reliability): Prevents re-triggering verification for the exact same
  // 6-digit code repeatedly (e.g. redundant notifications), while still
  // allowing a fresh attempt if the user edits and re-enters the same digits
  // after a failure (cleared on failure below).
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

    // FIX(reliability + perf): This fires no matter HOW a controller's text
    // changed — typed, pasted, or programmatically set via
    // `_fillBoxesVisually` (SMS autofill / platform autofill / paste). That
    // means auto-verify now works uniformly for every input path, instead of
    // being wired separately (and inconsistently) into each one.
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
      default:
        return 'Something went wrong. Please try again.';
    }
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
        duration: const Duration(seconds: 3),
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

  // FIX(perf): Ticks a ValueNotifier instead of calling setState() every
  // second. Previously this rebuilt the entire page (MediaQuery lookups,
  // layout math, hero image, all text) once a second for up to 30 seconds
  // straight — by far the biggest perf cost in this screen.
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
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': token});
      }
    } catch (_) {
      // Non-critical — silently ignore.
    }
  }

  bool _isValidIndianNumber(String digits) {
    if (digits.length != 10) return false;
    final first = int.tryParse(digits[0]) ?? 0;
    return first >= 6;
  }

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> _sendOtp({bool isResend = false}) async {
    final phone = _phoneController.text.trim().replaceAll(_nonDigits, '');

    if (!_isValidIndianNumber(phone)) {
      _showErrorSnack('Please enter a valid 10-digit Indian mobile number.');
      return;
    }
    if (!mounted) return;
    setState(() => _isSendingOtp = true);

    await _auth.verifyPhoneNumber(
      phoneNumber:         '+91$phone',
      forceResendingToken: isResend ? _resendToken : null,
      timeout:             const Duration(seconds: 60),

      verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;

        if (!_otpSent) {
          setState(() {
            _otpSent      = true;
            _isSendingOtp = false;
          });
          _slideCtrl.forward();
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          if (mounted) setState(() => _isSendingOtp = false);
        }

        if (!mounted) return;

        final smsCode = credential.smsCode;
        if (smsCode != null && smsCode.length == 6) {
          _fillBoxesVisually(smsCode);
          await Future.delayed(const Duration(milliseconds: 300));
        }

        if (mounted) await _signInWithCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isSendingOtp = false);
        _showErrorSnack(_friendlyError(e.code));
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
          const Duration(milliseconds: 350),
              () {
            if (mounted) _focusNodes[0].requestFocus();
          },
        );
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        if (mounted) _verificationId = verificationId;
      },
    );
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
      final userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null || !mounted) return;

      _saveFCMToken(user.uid);

      final userRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await userRef.get();
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
        }, SetOptions(merge: true));

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PersonalDetailsPage()),
        );
      }

      _verificationId = '';
    } on FirebaseAuthException catch (e) {
      // FIX(reliability): Allow retrying the same code after a failure
      // (e.g. user was mid-typing when an auto-verify attempt failed, or
      // wants to resubmit) instead of it being silently blocked forever.
      _lastAttemptedCode = '';
      if (mounted) _showErrorSnack(_friendlyError(e.code));
    } on TimeoutException {
      _lastAttemptedCode = '';
      if (mounted) {
        _showErrorSnack('Request timed out. Please check your connection.');
      }
    } catch (_) {
      _lastAttemptedCode = '';
      if (mounted) _showErrorSnack('Something went wrong. Please try again.');
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
  // FIX(perf): Wrapped in AnimatedBuilder listening ONLY to this box's own
  // controller. Typing a digit now only rebuilds this one small widget,
  // instead of setState() rebuilding the entire page on every keystroke.
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
              // FIX(reliability + perf): onChanged now ONLY handles focus
              // movement and paste distribution — nothing else. Fill color
              // is handled above via AnimatedBuilder, and auto-verify is
              // handled centrally by `_onOtpTextChanged`, so this can never
              // get out of sync with what the controllers actually contain.
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
    // FIX(perf): Split MediaQuery.of(context) into scoped aspect accessors.
    // MediaQuery.of() ties this whole build() to EVERY MediaQuery field
    // (size, viewInsets, padding, textScale, gestureSettings, ...), so any
    // unrelated change (e.g. system text-scale, a padding tweak from a
    // status-bar animation) would rebuild this whole page. The `*Of()`
    // accessors scope the dependency to just that one field.
    final screenSize        = MediaQuery.sizeOf(context);
    final screenW           = screenSize.width;
    final screenH           = screenSize.height;
    final viewInsetsBottom  = MediaQuery.viewInsetsOf(context).bottom;
    final devicePixelRatio  = MediaQuery.devicePixelRatioOf(context);

    final hPad  = screenW < 380 ? 16.0 : 22.0;
    final heroH = screenH < 680
        ? screenH * 0.20
        : screenH < 780
        ? screenH * 0.22
        : 180.0;

    final otpTotalW = screenW - hPad * 2;
    final rawBoxW   = (otpTotalW - 5 * 8) / 6;
    final boxSize   = rawBoxW.clamp(36.0, 52.0);

    if (_isVerifying) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _purple),
              SizedBox(height: 16),
              Text(
                'Verifying…',
                style: TextStyle(
                    fontSize:   14,
                    color:      Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:          Colors.white,
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
                        height:     heroH,
                        cacheWidth: (screenW * devicePixelRatio).toInt(),
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
                              text:  'swapnow',
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
                                onSubmitted:     (_) =>
                                _isSendingOtp ? null : _sendOtp(),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                // FIX(perf): No more setState() here — the
                                // Continue button below listens to this
                                // controller directly via AnimatedBuilder.
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

                      // FIX(perf): Only this button rebuilds as the phone
                      // number is typed, via AnimatedBuilder on
                      // _phoneController — not the whole page.
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

                            AutofillGroup(
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: List.generate(
                                    6, (i) => _buildOtpBox(i, boxSize)),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // FIX(perf): Only this small badge rebuilds as
                            // digits are entered, via ValueListenableBuilder
                            // on _codeNotifier.
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

                            // FIX(perf): This used to rebuild the whole page
                            // every second via setState(). Now the tick is
                            // isolated to just this small ValueListenableBuilder.
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