import 'package:credbro/start/payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class PaymentFailedPage extends StatefulWidget {
  final String errorCode;
  final String errorMessage;

  const PaymentFailedPage({
    super.key,
    required this.errorCode,
    required this.errorMessage,
  });

  @override
  State<PaymentFailedPage> createState() => _PaymentFailedPageState();
}

class _PaymentFailedPageState extends State<PaymentFailedPage>
    with TickerProviderStateMixin {
  // ── ANIMATION CONTROLLERS ─────────────────────────────────────────────────
  late AnimationController _iconController; // icon scale + shake
  late AnimationController _contentController; // staggered content fade+slide
  late AnimationController _buttonController; // button fade+slide
  late AnimationController _pulseController; // error ring pulse
  late AnimationController _shakeController; // icon shake

  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;
  late Animation<Offset> _errorCodeSlide;
  late Animation<double> _errorCodeFade;
  late Animation<Offset> _errorMsgSlide;
  late Animation<double> _errorMsgFade;
  late Animation<Offset> _adSlide;
  late Animation<double> _adFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _buttonFade;
  late Animation<double> _shakeAnim;

  BannerAd? _mediumRectangleAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;

  // ── RESPONSIVE HELPERS ────────────────────────────────────────────────────
  double _rf(BuildContext ctx, double base, {double min = 10, double max = 28}) {
    final w = MediaQuery.of(ctx).size.width;
    return (base * w / 375).clamp(min, max);
  }

  double _hPad(BuildContext ctx) =>
      (MediaQuery.of(ctx).size.width * 0.055).clamp(16.0, 28.0);

  @override
  void initState() {
    super.initState();

    // ── Icon: scale in with elastic bounce ───────────────────────────────────
    _iconController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));

    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _iconController, curve: Curves.elasticOut));

    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _iconController,
            curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));

    // ── Pulse ring around icon ────────────────────────────────────────────────
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: false);

    _ringScale = Tween<double>(begin: 0.85, end: 1.25).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _ringOpacity = Tween<double>(begin: 0.5, end: 0.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeIn));

    // ── Shake icon once after appearing ──────────────────────────────────────
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    // ── Staggered content: error code, message, ad ───────────────────────────
    _contentController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _errorCodeSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentController,
                curve: const Interval(0.0, 0.45, curve: Curves.easeOut)));
    _errorCodeFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _contentController,
            curve: const Interval(0.0, 0.45, curve: Curves.easeIn)));

    _errorMsgSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentController,
                curve: const Interval(0.2, 0.65, curve: Curves.easeOut)));
    _errorMsgFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _contentController,
            curve: const Interval(0.2, 0.65, curve: Curves.easeIn)));

    _adSlide =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentController,
                curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));
    _adFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn)));

    // ── Button ────────────────────────────────────────────────────────────────
    _buttonController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _buttonSlide =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
            CurvedAnimation(parent: _buttonController, curve: Curves.easeOut));
    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _buttonController, curve: Curves.easeIn));

    // ── Sequence ──────────────────────────────────────────────────────────────
    _iconController.forward().then((_) {
      if (!mounted) return;
      _shakeController.forward();
      _contentController.forward().then((_) {
        if (!mounted) return;
        _buttonController.forward();
      });
    });

    // ── Ad ────────────────────────────────────────────────────────────────────
    _loadAd();
  }

  void _loadAd() {
    _mediumRectangleAd = BannerAd(
      // ✅ Test ID — replace with your production ad-unit ID before release.
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Ad failed: ${error.message}');
          ad.dispose();
          // Null out the reference so dispose() below can't double-dispose
          // the same ad instance and so the UI falls back to placeholder.
          _mediumRectangleAd = null;
          if (mounted) setState(() => _isAdLoaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _iconController.dispose();
    _contentController.dispose();
    _buttonController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    // Safe: _mediumRectangleAd is nulled out in onAdFailedToLoad before its
    // own dispose() call, so this can never fire twice on the same instance.
    _mediumRectangleAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final sh = mq.size.height;
    final hPad = _hPad(context);

    final iconSize = (sw * 0.38).clamp(80.0, 120.0);
    final adWidth = (sw - hPad * 2).clamp(0.0, 300.0);
    final btnHeight = (sh * 0.065).clamp(48.0, 62.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: sh * 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: sh * 0.04),

              // ── ICON WITH PULSE RING ──────────────────────────────────────
              SizedBox(
                width: iconSize + 40,
                height: iconSize + 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Transform.scale(
                        scale: _ringScale.value,
                        child: Opacity(
                          opacity: _ringOpacity.value,
                          child: Container(
                            width: iconSize * 1.15,
                            height: iconSize * 1.15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE53935),
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Soft glow background circle
                    Container(
                      width: iconSize * 1.05,
                      height: iconSize * 1.05,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFEBEE),
                      ),
                    ),

                    // Icon: scale + shake
                    AnimatedBuilder(
                      animation: _shakeAnim,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(_shakeAnim.value, 0),
                        child: child,
                      ),
                      child: FadeTransition(
                        opacity: _iconOpacity,
                        child: ScaleTransition(
                          scale: _iconScale,
                          child: SvgPicture.asset(
                            'assets/images/unsuccess.svg',
                            width: iconSize,
                            height: iconSize,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: sh * 0.03),

              // ── TITLE ─────────────────────────────────────────────────────
              SlideTransition(
                position: _errorCodeSlide,
                child: FadeTransition(
                  opacity: _errorCodeFade,
                  child: Text(
                    "Payment Unsuccessful",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _rf(context, 22, min: 17, max: 26),
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),

              SizedBox(height: sh * 0.01),

              // ── ERROR CODE CHIP ───────────────────────────────────────────
              SlideTransition(
                position: _errorCodeSlide,
                child: FadeTransition(
                  opacity: _errorCodeFade,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: sh * 0.008),
                    padding: EdgeInsets.symmetric(
                      horizontal: _rf(context, 12, min: 8, max: 16),
                      vertical: _rf(context, 5, min: 3, max: 8),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(20),
                      border:
                      Border.all(color: const Color(0xFFEF9A9A), width: 1),
                    ),
                    child: Text(
                      // Best-effort: code may originate from Razorpay or be
                      // user-influenced in edge cases, so it's rendered as
                      // plain text only — never used to build markup/HTML.
                      "Error Code: ${widget.errorCode}",
                      style: TextStyle(
                        fontSize: _rf(context, 12, min: 10, max: 14),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE53935),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: sh * 0.008),

              // ── ERROR MESSAGE ─────────────────────────────────────────────
              SlideTransition(
                position: _errorMsgSlide,
                child: FadeTransition(
                  opacity: _errorMsgFade,
                  child: Text(
                    widget.errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _rf(context, 14, min: 11, max: 16),
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ),
              ),

              SizedBox(height: sh * 0.035),

              // ── AD BANNER ────────────────────────────────────────────────
              SlideTransition(
                position: _adSlide,
                child: FadeTransition(
                  opacity: _adFade,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: adWidth,
                        minWidth: 0,
                      ),
                      child: AspectRatio(
                        aspectRatio: 300 / 250,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.09),
                                spreadRadius: 1,
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: (_isAdLoaded && _mediumRectangleAd != null)
                                ? AdWidget(ad: _mediumRectangleAd!)
                                : const Center(
                              child: Text(
                                "Ad Banner",
                                style:
                                TextStyle(color: Colors.black38),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: sh * 0.04),

              // ── RETRY BUTTON ──────────────────────────────────────────────
              SlideTransition(
                position: _buttonSlide,
                child: FadeTransition(
                  opacity: _buttonFade,
                  child: SizedBox(
                    width: double.infinity,
                    height: btnHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? const LinearGradient(
                            colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)])
                            : const LinearGradient(
                          colors: [
                            Color(0xFF5800B3),
                            Color(0xFF26004D)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: _isLoading
                            ? []
                            : [
                          BoxShadow(
                            color: const Color(0xFF5800B3)
                                .withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _isLoading ? null : _onRetry,
                        child: _isLoading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Try Again",
                              style: TextStyle(
                                fontSize:
                                _rf(context, 16, min: 13, max: 18),
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: sh * 0.02),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onRetry() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    // pushReplacement instead of push: prevents the back stack from
    // accumulating Fail → Pay → Fail → Pay chains.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PaymentPage()),
    );
  }
}