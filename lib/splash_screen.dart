import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_svg/svg.dart';
import 'package:amoeba/chats/notification_service.dart';
import 'package:amoeba/logs/wrapper.dart';

class SplashScreen extends StatefulWidget {
  // C1 fix: navigatorKey passed directly — no unsafe widget tree cast
  final GlobalKey<NavigatorState> navigatorKey;
  // NEW: the in-flight Firebase.initializeApp() future from main(). Splash
  // now owns awaiting this instead of main.dart awaiting it before
  // runApp() — see the fix note in main.dart for why that mattered.
  final Future<FirebaseApp> firebaseInit;
  // NEW: the in-flight App Check activation (+ first token fetch) future
  // from main(). Splash waits on this too, alongside route-resolution,
  // before handing off to Wrapper -- see the fix note on appCheckReady in
  // main.dart for the "signs out on every launch" bug this closes.
  final Future<void> appCheckReady;

  const SplashScreen({
    super.key,
    required this.navigatorKey,
    required this.firebaseInit,
    required this.appCheckReady,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Controllers ────────────────────────────────────────────────
  late AnimationController _bgController;
  late AnimationController _entryController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late AnimationController _shimmerController;
  late AnimationController _ringController;

  // ── Entry animations ───────────────────────────────────────────
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<Offset> _logoSlide;
  late Animation<double> _taglineOpacity;
  late Animation<Offset> _taglineSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _pillOpacity;
  late Animation<double> _pillScale;

  // ── Continuous animations ──────────────────────────────────────
  late Animation<double> _pulse;
  late Animation<double> _shimmer;
  late Animation<double> _ring;

  // ── Particles ─────────────────────────────────────────────────
  // FIX(perf): 30 -> 16. Combined with scoping the particle canvas to its
  // own controller below (instead of rebuilding as part of one giant merged
  // listener), this was the other big chunk of steady per-frame cost.
  final List<_Particle> _particles = [];
  final math.Random _rng = math.Random();

  // ── State ─────────────────────────────────────────────────────
  bool _showContent = false;
  bool _initFailed = false;
  late Future<FirebaseApp> _firebaseInit;

  @override
  void initState() {
    super.initState();

    _firebaseInit = widget.firebaseInit;

    _buildParticles();
    _setupAnimations();

    // Purely visual -- doesn't touch Firebase -- so it starts on the very
    // first frame regardless of whether Firebase.initializeApp() has
    // resolved yet.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;                          // C2 fix: mounted guard
      _entryController.forward();
      setState(() => _showContent = true);
    });

    // Everything that actually needs Firebase core (FirebaseAuth,
    // Firestore, notifications, and the eventual navigation to Wrapper)
    // is gated behind this instead of assuming Firebase.initializeApp()
    // already finished before this widget was even built.
    _bootstrapAfterFirebase();
  }

  Future<void> _bootstrapAfterFirebase() async {
    try {
      await _firebaseInit;
    } catch (e) {
      debugPrint('[SwapNow] Splash: Firebase.initializeApp failed: $e');
      if (mounted) setState(() => _initFailed = true);
      return;
    }

    // FIX (white-screen after splash): warm Wrapper's routing decision now,
    // in parallel with the splash animation, instead of letting it start
    // cold the moment Wrapper mounts. This is a SharedPreferences read + a
    // Firestore `users/{uid}` read -- RouteResolver caches the result so
    // Wrapper's FutureBuilder just picks up an already-finished Future
    // instead of showing its own blank `_InstantScreen` placeholder while
    // it waits.
    //
    // FIX(startup speed): navigation used to be a flat, unconditional
    // Future.delayed(4500ms) -- paid IN FULL every single launch, on top
    // of whatever Firebase.initializeApp() itself took, regardless of how
    // fast this route-resolve actually finished. That's what was showing
    // up as several extra seconds before the bottom nav appeared. Instead:
    // race a short minimum "branding" delay against the real route-resolve
    // future, capped so a slow/flaky connection can't hang the splash
    // indefinitely -- on a fast connection this leaves in ~1.1s; on a slow
    // one it waits (up to the cap) for the resolve so Wrapper doesn't have
    // to show its own blank frame right after this one.
    final minSplashTime =
    Future<void>.delayed(const Duration(milliseconds: 1100));

    // FIX(re-login-every-launch, root cause): App Check's activation (+
    // first token fetch, see main.dart) has to finish BEFORE the very
    // first authenticated Firestore read of this session below -- not
    // just before Splash navigates away. Defining it first and awaiting
    // it INSIDE the routeReady chain (rather than only racing it
    // alongside routeReady) is what actually closes the race: previously
    // this Firestore call and App Check activation ran concurrently, so
    // whichever happened to finish first was down to luck -- and once
    // Splash got faster, the Firestore call started winning that race
    // consistently, which is what was getting misread as an invalid
    // session. Capped with its own timeout so a genuinely broken App
    // Check setup degrades to "proceed anyway" instead of stalling login.
    final appCheckReady = widget.appCheckReady
        .timeout(const Duration(milliseconds: 3000), onTimeout: () {})
        .catchError((e) {
      debugPrint('[SwapNow] Splash: appCheckReady wait failed: $e');
    });

    final routeReady = FirebaseAuth.instance
        .authStateChanges()
        .first
        .then<Widget?>((user) async {
      if (user == null) return null;
      await appCheckReady; // ordering fix -- see appCheckReady above
      return await RouteResolver.instance.resolve(user);
    })
        .timeout(const Duration(milliseconds: 6000), onTimeout: () => null)
        .catchError((e) {
      debugPrint('[SwapNow] Splash route prefetch failed: $e');
      return null;
    });

    // M2 fix: wrapped in try/catch so a notification init failure
    // never prevents the splash from navigating to Wrapper
    // NotificationService is a singleton (M1 fix) so init runs exactly once
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;                          // C2 fix: mounted guard
      try {
        // init() internally handles getInitialMessage() for terminated-state
        // taps — no handleMessage() call needed here (M3 fix: removed)
        await NotificationService().init(widget.navigatorKey);
      } catch (e, stack) {
        // M2 fix: log and continue — app works, notifications silently fail
        debugPrint('[SwapNow] NotificationService init failed: $e\n$stack');
      }
    });

    // Navigate to Wrapper once ready — C2 fix: mounted check before push.
    // (appCheckReady doesn't need to be listed separately here: routeReady
    // already awaits it internally above, and when there's no signed-in
    // user there's no Firestore read to protect, so nothing needs it.)
    await Future.wait([minSplashTime, routeReady]);
    if (!mounted) return;                            // C2 fix: mounted guard
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const Wrapper(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _retryFirebaseInit() {
    setState(() {
      _initFailed = false;
      _firebaseInit = Firebase.initializeApp();
    });
    _bootstrapAfterFirebase();
  }

  void _setupAnimations() {
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _logoScale = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
      ),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    ));

    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    ));

    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.50, 0.75, curve: Curves.easeOut),
      ),
    );
    _subtitleSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.50, 0.75, curve: Curves.easeOut),
    ));

    _pillOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.70, 1.0, curve: Curves.easeOut),
      ),
    );
    _pillScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.70, 1.0, curve: Curves.elasticOut),
      ),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _ring = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  void _buildParticles() {
    for (int i = 0; i < 16; i++) {
      _particles.add(_Particle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        radius: _rng.nextDouble() * 3.5 + 1.0,
        speed: _rng.nextDouble() * 0.4 + 0.15,
        phase: _rng.nextDouble() * math.pi * 2,
        opacity: _rng.nextDouble() * 0.5 + 0.15,
        drift: (_rng.nextDouble() - 0.5) * 0.12,
      ));
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _entryController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _shimmerController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 380;
    final isTablet = size.width >= 600;

    final logoSize = isTablet
        ? size.width * 0.28
        : isSmall
        ? size.width * 0.52
        : size.width * 0.42;

    final taglineFontSize = isTablet ? 38.0 : isSmall ? 26.0 : 32.0;
    final subtitleFontSize = isTablet ? 16.0 : isSmall ? 12.0 : 14.0;

    // FIX(perf): This used to be a single
    // `Listenable.merge([_bgController, _entryController, _pulseController,
    // _particleController, _shimmerController, _ringController])` wrapping
    // the ENTIRE Stack (background gradients, 30-particle canvas, rings,
    // shimmer text, content layout). That meant a tick from ANY of those 6
    // independently-running controllers rebuilt EVERYTHING — effectively a
    // full-tree rebuild ~60 times a second for the whole splash duration,
    // regardless of which single piece actually needed to change. On
    // weaker devices that's exactly the kind of load that shows up as
    // dropped frames / stutter / a splash that "isn't working properly".
    //
    // Now each piece is scoped to only the controller it actually depends
    // on, so e.g. a particle-controller tick only rebuilds the particle
    // canvas, not the background gradients or the ring. `_buildLogo` (pulse)
    // and `_buildShimmerText` (shimmer) already had their own scoped
    // AnimatedBuilders internally — this just stops the outer merge from
    // needlessly re-running everything around them too.
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) => _buildBackground(size),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) => CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  progress: _particleController.value,
                  size: size,
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) => _buildRings(size, logoSize),
          ),
          if (_showContent && !_initFailed)
            _buildContent(
              size: size,
              logoSize: logoSize,
              taglineFontSize: taglineFontSize,
              subtitleFontSize: subtitleFontSize,
            ),
          // NEW: rendered on top of the still-visible animated background
          // (not a separate blank screen) if Firebase.initializeApp()
          // itself fails -- e.g. no network on a genuinely cold first
          // launch. Previously this case wasn't handled at splash level at
          // all.
          if (_initFailed) _buildInitFailedOverlay(),
        ],
      ),
    );
  }

  Widget _buildInitFailedOverlay() {
    return Container(
      color: const Color(0xFF0D001A).withOpacity(0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/images/no_connection.svg',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
                placeholderBuilder: (context) => const Icon(
                  Icons.wifi_off_rounded,
                  size: 56,
                  color: Color(0xFFBB66FF),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Couldn't start SwapNow",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Please check your internet connection and try again.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A0DAD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                onPressed: _retryFirebaseInit,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground(Size size) {
    final t = _bgController.value;
    final angle = t * math.pi * 2;

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0D001A)),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.1,
                colors: [Color(0xFF2E0060), Color(0xFF0D001A)],
              ),
            ),
          ),
          Positioned(
            left: size.width * 0.1 + math.cos(angle) * size.width * 0.08,
            top: size.height * 0.08 + math.sin(angle) * size.height * 0.06,
            child: _buildOrb(size.width * 0.7, const Color(0xFF6B0FD4), 0.35),
          ),
          Positioned(
            right: size.width * 0.05 +
                math.cos(-angle * 0.7) * size.width * 0.07,
            bottom: size.height * 0.1 +
                math.sin(-angle * 0.7) * size.height * 0.06,
            child: _buildOrb(size.width * 0.65, const Color(0xFF3D00A0), 0.3),
          ),
          Positioned(
            left: size.width * 0.25 +
                math.cos(angle * 1.3) * size.width * 0.05,
            top: size.height * 0.35 +
                math.sin(angle * 1.3) * size.height * 0.04,
            child: _buildOrb(size.width * 0.45, const Color(0xFFAB00FF), 0.12),
          ),
          // REMOVED: a full-screen Opacity(0.04) + CustomPaint(_NoisePainter())
          // layer that drew (width * height / 60) individual circles onto a
          // separate compositing layer purely for a subtle grain texture.
          // On a ~1080x2400 phone screen that's on the order of 40,000+
          // drawCircle calls for a barely-visible effect — not worth the
          // GPU/CPU cost on a splash screen that's supposed to feel instant.
        ],
      ),
    );
  }

  Widget _buildOrb(double diameter, Color color, double opacity) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(opacity), color.withOpacity(0)],
        ),
      ),
    );
  }

  Widget _buildRings(Size size, double logoSize) {
    final ringProgress = _ring.value;
    final ringOpacity = (1.0 - ringProgress).clamp(0.0, 1.0);
    final maxRadius = logoSize * 1.4;
    final ringRadius = logoSize * 0.6 + ringProgress * maxRadius;

    return Center(
      child: Opacity(
        opacity: ringOpacity * 0.4,
        child: Container(
          width: ringRadius * 2,
          height: ringRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFBB66FF),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required Size size,
    required double logoSize,
    required double taglineFontSize,
    required double subtitleFontSize,
  }) {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 3),
          FadeTransition(
            opacity: _logoOpacity,
            child: SlideTransition(
              position: _logoSlide,
              child: ScaleTransition(
                scale: _logoScale,
                child: _buildLogo(logoSize),
              ),
            ),
          ),
          SizedBox(height: size.height * 0.01),
          FadeTransition(
            opacity: _taglineOpacity,
            child: SlideTransition(
              position: _taglineSlide,
              child: _buildShimmerText(
                'Amoeba',
                fontSize: taglineFontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(height: size.height * 0.012),
          FadeTransition(
            opacity: _subtitleOpacity,
            child: SlideTransition(
              position: _subtitleSlide,
              child: Text(
                'Exchange. Instantly. Effortlessly.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: subtitleFontSize,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const Spacer(flex: 3),
          FadeTransition(
            opacity: _pillOpacity,
            child: ScaleTransition(
              scale: _pillScale,
              child: _buildCraftedLabel(),
            ),
          ),
          SizedBox(height: size.height * 0.05),
        ],
      ),
    );
  }

  Widget _buildLogo(double size) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulse.value,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 1.25,
                height: size * 1.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      // FIX(perf): blurRadius 60 / spreadRadius 20 -> 40 / 12.
                      // This shadow recomputes every pulse frame; a smaller
                      // blur radius is noticeably cheaper for the GPU to
                      // rasterize while still reading as a soft glow.
                      color: const Color(0xFF9B30FF).withOpacity(
                        0.3 + (_pulse.value - 0.85) / 0.2 * 0.2,
                      ),
                      blurRadius: 40,
                      spreadRadius: 12,
                    ),
                  ],
                ),
              ),
              Container(
                width: size * 1.05,
                height: size * 1.05,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7A1FFF).withOpacity(0.25),
                      const Color(0xFF3D0080).withOpacity(0.10),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFBB66FF).withOpacity(0.3),
                    width: 1.0,
                  ),
                ),
              ),
              SizedBox(
                width: size * 0.75,
                height: size * 0.75,
                child: Image.asset(
                  'assets/images/ic_notification.png',
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerText(
      String text, {
        required double fontSize,
        required FontWeight fontWeight,
        required double letterSpacing,
      }) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
              colors: [
                Colors.white,
                Colors.white,
                Colors.white.withOpacity(0.95),
                const Color(0xFFE0AAFF),
                Colors.white,
              ],
              transform: _ShimmerTransform(_shimmer.value),
            ).createShader(bounds);
          },
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCraftedLabel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Crafted with ',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const Icon(Icons.favorite, color: Color(0xFFFF4D6D), size: 13),
        Text(
          ' in India',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 5),
        const Text('🇮🇳', style: TextStyle(fontSize: 13)),
      ],
    );
  }
}

// ── Shimmer gradient transform ─────────────────────────────────────────────
class _ShimmerTransform extends GradientTransform {
  const _ShimmerTransform(this.slide);
  final double slide;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slide, 0, 0);
  }
}

// ── Particle model ─────────────────────────────────────────────────────────
class _Particle {
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
  final double opacity;
  final double drift;

  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.opacity,
    required this.drift,
  });
}

// ── Particle painter ───────────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Size size;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final p in particles) {
      final t = (progress * p.speed + p.phase / (math.pi * 2)) % 1.0;
      final yPos = (p.y - t) % 1.0;
      final xWobble = math.sin(t * math.pi * 2 + p.phase) * p.drift;
      final xPos = (p.x + xWobble).clamp(0.0, 1.0);

      final fadeIn = (t < 0.1) ? t / 0.1 : 1.0;
      final fadeOut = (t > 0.85) ? (1.0 - t) / 0.15 : 1.0;
      final alpha = p.opacity * fadeIn * fadeOut;

      final paint = Paint()
        ..color = const Color(0xFFCC88FF).withOpacity(alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

      canvas.drawCircle(
        Offset(xPos * canvasSize.width, yPos * canvasSize.height),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}