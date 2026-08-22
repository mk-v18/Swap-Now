import 'package:flutter/material.dart';

// ── Payment Processing screen ────────────────────────────────────────────
//
// Shown as its own route the instant Razorpay hands control back to us
// (payment closed on Razorpay's side) while we call the `verify*Payment`
// Cloud Function. Previously this gap had no dedicated UI — at best a
// circular spinner inline on a button — so the app could look frozen or
// jump straight from the form to Success/Failure with no explanation.
//
// This page does not do any work itself. The caller pushes it, awaits the
// verification call, then uses Navigator.pushReplacement to swap it out for
// PaymentSuccessPage or PaymentFailedPage. Back navigation is blocked while
// this is on screen — a payment is in flight and shouldn't be interrupted.
class PaymentProcessingPage extends StatefulWidget {
  final String title;
  final String message;

  const PaymentProcessingPage({
    super.key,
    this.title = "Processing Payment",
    this.message = "Please wait while we confirm your payment with the bank.",
  });

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

class _PaymentProcessingPageState extends State<PaymentProcessingPage>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isSmall = w < 360;
    final isLarge = w >= 600;
    final ringOuter = (w * 0.36).clamp(100.0, 168.0);

    return PopScope(
      // A verification call is in flight — leaving this screen mid-call
      // would strand the user between "paid" and "confirmed". They land on
      // Success/Failure automatically once the caller gets a result.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isLarge ? 40 : 24),
                child: FadeTransition(
                  opacity: _fadeCtrl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: ringOuter,
                        height: ringOuter,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Soft pulsing glow behind the ring.
                            AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (_, child) => Transform.scale(
                                scale: 0.92 + (_pulseCtrl.value * 0.10),
                                child: child,
                              ),
                              child: Container(
                                width: ringOuter,
                                height: ringOuter,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFF3E9FF),
                                ),
                              ),
                            ),
                            // Rotating progress ring.
                            RotationTransition(
                              turns: _spinCtrl,
                              child: SizedBox(
                                width: ringOuter * 0.78,
                                height: ringOuter * 0.78,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 4.5,
                                  valueColor: AlwaysStoppedAnimation(
                                      Color(0xFF5800B3)),
                                  backgroundColor: Color(0x1F5800B3),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.verified_user_rounded,
                              size: ringOuter * 0.32,
                              color: const Color(0xFF5800B3),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isLarge ? 32 : 24),

                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmall ? 18 : (isLarge ? 25 : 21),
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          letterSpacing: -0.2,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmall ? 13 : 15,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                      ),

                      SizedBox(height: isLarge ? 22 : 16),

                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6E5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFFFD98E), width: 1),
                        ),
                        child: Text(
                          "Please don't close the app or press back",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isSmall ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB07A00),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}