import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../logs/wrapper.dart';
import '../pages/bottom_navigation.dart';

class StartingPage extends StatefulWidget {
  const StartingPage({super.key});

  @override
  State<StartingPage> createState() => _StartingPageState();
}

class _StartingPageState extends State<StartingPage>
    with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  bool _isPressed = false;

  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  static const Color _primary = Color(0xFF5800B3);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(
        parent: _pulseController!,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  // ── Mark onboarding complete in Firestore ──────────────────────────────────
  // Called from both "Start Exchanging" and "Skip" so Wrapper never
  // redirects a returning user back to StartingPage after they've seen it.
  Future<void> _markOnboardingDone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'onboardingStep': 'done'});
    } catch (e) {
      // Non-fatal — Wrapper will show StartingPage again on next cold start,
      // which is safe. Never block navigation over a Firestore write failure.
      debugPrint('[SwapNow] onboardingStep update failed: $e');
    }
  }

  // ── Start Exchanging button ────────────────────────────────────────────────
  Future<void> _handleExchange() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _markOnboardingDone();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BottomNavigation()),
    );
  }

  // ── Skip button ────────────────────────────────────────────────────────────
  Future<void> _handleSkip() async {
    await _markOnboardingDone();
    if (!mounted) return;
    // Push Wrapper so it re-evaluates state and routes to BottomNavigation
    // cleanly — avoids duplicating the routing logic here.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Wrapper()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    final hPad = (size.width * 0.06).clamp(20.0, 60.0);
    final titleFontSize = (size.width * 0.063).clamp(22.0, 38.0);
    final subtitleFontSize = (size.width * 0.034).clamp(13.0, 18.0);
    final skipFontSize = (size.width * 0.035).clamp(13.0, 16.0);
    final imageWidth = isTablet ? size.width * 0.5 : size.width * 0.78;
    final buttonHeight = (size.height * 0.072).clamp(52.0, 68.0);
    final buttonFontSize = (size.width * 0.042).clamp(14.0, 18.0);


    return Scaffold(
      backgroundColor: Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // ── Background ───────────────────────────────────────────────────

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: size.height * 0.025),

                  // ── Skip button ─────────────────────────────────────────
                  Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: _isProcessing ? null : _handleSkip,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Skip',
                              style: GoogleFonts.poppins(
                                color: _primary,
                                fontSize: skipFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded,
                                color: _primary.withOpacity(0.8), size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: size.height * 0.2),

                  // ── Illustration ────────────────────────────────────────
                  Image.asset(
                    'assets/images/boxes.png',
                    width: imageWidth,
                    fit: BoxFit.contain,
                  ),

                  SizedBox(height: size.height * 0.020),

                  // ── Text section ────────────────────────────────────────
                  Text(
                    "Exchange What You Have,\nGet What You Need.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5800B3),
                      height: 1.25,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: size.height * 0.012),
                  Text(
                    "Every Product Deserves Another Chance",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: subtitleFontSize,
                      color: const Color(0xFF5800B3).withOpacity(0.65),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                  SizedBox(height: size.height * 0.035),


                  // ── Exchange button ─────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.only(bottom: size.height * 0.025),
                    child: AnimatedScale(
                      scale: _isPressed ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: ScaleTransition(
                        scale: (_isProcessing || _pulseAnimation == null)
                            ? const AlwaysStoppedAnimation(1.0)
                            : _pulseAnimation!,
                        child: GestureDetector(
                          onTapDown: (_) => setState(() => _isPressed = true),
                          onTapUp: (_) => setState(() => _isPressed = false),
                          onTapCancel: () => setState(() => _isPressed = false),
                          onTap: _isProcessing ? null : _handleExchange,
                          child: Container(
                            width: double.infinity,
                            height: buttonHeight,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF7B10E8),
                                  Color(0xFF5800B3),
                                  Color(0xFF26004D),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF5800B3).withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: _isProcessing
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
                                  'Start Exchanging',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: buttonFontSize,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 20),
                              ],
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
        ],
      ),
    );
  }
}