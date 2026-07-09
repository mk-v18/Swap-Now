import 'package:credbro/start/starting_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ── Responsive helper ──────────────────────────────────────────────────────
class _R {
  final double w;
  final double h;
  final bool isSmall; // < 360 dp  (compact phones)
  final bool isLarge; // ≥ 600 dp  (tablets / foldables)

  const _R({
    required this.w,
    required this.h,
    required this.isSmall,
    required this.isLarge,
  });

  factory _R.of(BuildContext ctx) {
    final s = MediaQuery.of(ctx).size;
    return _R(
      w: s.width,
      h: s.height,
      isSmall: s.width < 360,
      isLarge: s.width >= 600,
    );
  }

  double wf(double f, {double min = 0, double max = double.infinity}) =>
      (w * f).clamp(min, max);
  double hf(double f, {double min = 0, double max = double.infinity}) =>
      (h * f).clamp(min, max);

  double get hPad => isLarge ? 40 : 24;
  double get titleSz => isSmall ? 18 : (isLarge ? 26 : 21);
  double get bodySz => isSmall ? 12 : (isLarge ? 16 : 14);
  double get btnH => isSmall ? 50 : (isLarge ? 64 : 56);
  double get btnR => isLarge ? 18 : 14;
}

class PaymentSuccessPage extends StatefulWidget {
  final String paymentId;
  final String time;

  const PaymentSuccessPage({
    super.key,
    required this.paymentId,
    required this.time,
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with TickerProviderStateMixin {
  // ── ANIMATION CONTROLLERS ─────────────────────────────────────────────────
  late AnimationController _iconController; // icon scale in
  late AnimationController _contentController; // staggered content fade+slide
  late AnimationController _buttonController; // button fade+slide
  late AnimationController _pulseController; // success ring pulse
  late AnimationController _popController; // icon celebratory pop

  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleFade;
  late Animation<Offset> _cardSlide;
  late Animation<double> _cardFade;
  late Animation<Offset> _adSlide;
  late Animation<double> _adFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _buttonFade;
  late Animation<double> _popAnim;

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;

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

    // ── Small celebratory "pop" on the icon after appearing ────────────────────
    _popController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _popAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 0.97), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _popController, curve: Curves.easeInOut));

    // ── Staggered content: title/subtitle, detail card, ad ─────────────────────
    _contentController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _titleSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentController,
                curve: const Interval(0.0, 0.45, curve: Curves.easeOut)));
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _contentController,
            curve: const Interval(0.0, 0.45, curve: Curves.easeIn)));

    _cardSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentController,
                curve: const Interval(0.2, 0.65, curve: Curves.easeOut)));
    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
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
      _popController.forward();
      _contentController.forward().then((_) {
        if (!mounted) return;
        _buttonController.forward();
      });
    });

    // ── AdMob Medium Rectangle ──
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
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
          debugPrint('Banner ad failed: ${error.message}');
          ad.dispose();
          // Null out so dispose() below never touches an already-disposed
          // ad instance, and the UI falls back to the placeholder.
          _bannerAd = null;
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
    _popController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  String get _formattedTime {
    try {
      return DateFormat("dd MMM yyyy, hh:mm a")
          .format(DateTime.parse(widget.time));
    } catch (_) {
      return widget.time;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final r = _R.of(context);
    final iconSize = r.wf(0.42, min: 80, max: 120);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          // Caps layout width on tablets
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: r.hPad,
                vertical: r.hf(0.04, min: 20, max: 48),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Animated success illustration with pulse ring ───────
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
                                    color: const Color(0xFF43A047),
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
                            color: Color(0xFFE8F5E9),
                          ),
                        ),

                        // Icon: scale in + celebratory pop
                        AnimatedBuilder(
                          animation: _popAnim,
                          builder: (_, child) => Transform.scale(
                            scale: _popAnim.value,
                            child: child,
                          ),
                          child: FadeTransition(
                            opacity: _iconOpacity,
                            child: ScaleTransition(
                              scale: _iconScale,
                              child: SvgPicture.asset(
                                'assets/images/success.svg',
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

                  SizedBox(height: r.hf(0.025, min: 14, max: 28)),

                  // ── Title + subtitle (staggered) ────────────────────────
                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleFade,
                      child: Column(
                        children: [
                          Text(
                            "Payment Successful",
                            style: TextStyle(
                              fontSize: r.titleSz,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: r.hf(0.008, min: 4, max: 10)),
                          Text(
                            "Your account has been activated successfully.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: r.bodySz - 0.5,
                              color: Colors.black45,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: r.hf(0.022, min: 12, max: 24)),

                  // ── Payment detail card (staggered) ─────────────────────
                  SlideTransition(
                    position: _cardSlide,
                    child: FadeTransition(
                      opacity: _cardFade,
                      child: _DetailCard(
                        paymentId: widget.paymentId,
                        formattedTime: _formattedTime,
                        resp: r,
                      ),
                    ),
                  ),

                  SizedBox(height: r.hf(0.028, min: 16, max: 32)),

                  // ── AdMob banner (staggered) ─────────────────────────────
                  SlideTransition(
                    position: _adSlide,
                    child: FadeTransition(
                      opacity: _adFade,
                      child: _AdBanner(
                        isLoaded: _isAdLoaded,
                        ad: _bannerAd,
                        resp: r,
                      ),
                    ),
                  ),

                  SizedBox(height: r.hf(0.04, min: 20, max: 40)),

                  // ── Continue button (staggered) ─────────────────────────
                  SlideTransition(
                    position: _buttonSlide,
                    child: FadeTransition(
                      opacity: _buttonFade,
                      child: SizedBox(
                        width: double.infinity,
                        height: r.btnH,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(r.btnR),
                            ),
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                          ),
                          onPressed: _isLoading ? null : _onContinue,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(r.btnR),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                  const Color(0xFF5800B3).withOpacity(0.32),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Container(
                              alignment: Alignment.center,
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Continue",
                                    style: TextStyle(
                                      fontSize: r.bodySz + 1,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onContinue() async {
    setState(() => _isLoading = true);
    // pushReplacement instead of push: a user landing back on "Payment
    // Successful" via the back button after they've already continued
    // is confusing and lets them re-trigger downstream onboarding logic.
    // No post-navigation setState needed — this widget is being removed.
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const StartingPage()),
    );
  }
}

// ── Payment detail card ────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.paymentId,
    required this.formattedTime,
    required this.resp,
  });

  final String paymentId;
  final String formattedTime;
  final _R resp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: resp.hPad,
        vertical: resp.hf(0.018, min: 12, max: 20),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF5800B3).withOpacity(0.15),
        ),
      ),
      child: Column(
        children: [
          _DetailRow(
            label: "Payment ID",
            value: paymentId,
            resp: resp,
          ),
          Divider(
            height: resp.hf(0.025, min: 14, max: 22),
            color: const Color(0xFF5800B3).withOpacity(0.1),
          ),
          _DetailRow(
            label: "Date & Time",
            value: formattedTime,
            resp: resp,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.resp,
  });

  final String label;
  final String value;
  final _R resp;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label  ",
          style: TextStyle(
            fontSize: resp.bodySz - 1,
            color: Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: resp.bodySz - 1,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── AdMob banner ───────────────────────────────────────────────────────────

class _AdBanner extends StatelessWidget {
  const _AdBanner({
    required this.isLoaded,
    required this.ad,
    required this.resp,
  });

  final bool isLoaded;
  final BannerAd? ad;
  final _R resp;

  // Medium Rectangle is a fixed 300×250 IAB unit — never resize it.
  static const double _adW = 300;
  static const double _adH = 250;

  @override
  Widget build(BuildContext context) {
    // On very small screens, scale down proportionally
    final scale = (resp.w - resp.hPad * 2) < _adW
        ? (resp.w - resp.hPad * 2) / _adW
        : 1.0;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: _adW,
        height: _adH,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: (isLoaded && ad != null)
              ? AdWidget(ad: ad!)
              : const Center(
            child: Text(
              "Ad Banner",
              style: TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}