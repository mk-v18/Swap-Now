import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:credbro/chats/notification_service.dart';
import 'package:credbro/logs/wrapper.dart';

class SplashScreen extends StatefulWidget {
  // C1 fix: navigatorKey passed directly — no unsafe widget tree cast
  final GlobalKey<NavigatorState> navigatorKey;
  const SplashScreen({super.key, required this.navigatorKey});

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
  final List<_Particle> _particles = [];
  final math.Random _rng = math.Random();

  // ── State ─────────────────────────────────────────────────────
  bool _showContent = false;

  @override
  void initState() {
    super.initState();

    _buildParticles();
    _setupAnimations();

    // Start entry animation after first frame settles
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;                          // C2 fix: mounted guard
      _entryController.forward();
      setState(() => _showContent = true);
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

    // Navigate to Wrapper after splash — C2 fix: mounted check before push
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (!mounted) return;                          // C2 fix: mounted guard
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const Wrapper(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
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
    for (int i = 0; i < 30; i++) {
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

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _bgController,
          _entryController,
          _pulseController,
          _particleController,
          _shimmerController,
          _ringController,
        ]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(size),
              CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  progress: _particleController.value,
                  size: size,
                ),
              ),
              _buildRings(size, logoSize),
              if (_showContent)
                _buildContent(
                  size: size,
                  logoSize: logoSize,
                  taglineFontSize: taglineFontSize,
                  subtitleFontSize: subtitleFontSize,
                ),
            ],
          );
        },
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
          Opacity(
            opacity: 0.04,
            child: CustomPaint(painter: _NoisePainter(), size: size),
          ),
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
          SizedBox(height: size.height * 0.03),
          FadeTransition(
            opacity: _taglineOpacity,
            child: SlideTransition(
              position: _taglineSlide,
              child: _buildShimmerText(
                'SwapNow',
                fontSize: taglineFontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
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
                      color: const Color(0xFF9B30FF).withOpacity(
                        0.3 + (_pulse.value - 0.85) / 0.2 * 0.2,
                      ),
                      blurRadius: 60,
                      spreadRadius: 20,
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

// ── Noise painter ──────────────────────────────────────────────────────────
class _NoisePainter extends CustomPainter {
  final math.Random _rng = math.Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final w = size.width.toInt();
    final h = size.height.toInt();
    for (int i = 0; i < w * h ~/ 60; i++) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(_NoisePainter old) => false;
}