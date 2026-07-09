import 'package:credbro/Advertisement/location_ad.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuggestionsPage extends StatefulWidget {
  const SuggestionsPage({super.key});

  @override
  State<SuggestionsPage> createState() => _SuggestionsPageState();
}

class _SuggestionsPageState extends State<SuggestionsPage> {
  final TextEditingController _suggestionController = TextEditingController();
  bool _isLoading = false;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _lightPurple = Color(0xFFF3EEFF);
  static const _green       = Color(0xFF1B8A4C);
  static const _red         = Color(0xFFB00020);

  double _cl(double v, double mn, double mx) =>
      v < mn ? mn : (v > mx ? mx : v);

  @override
  void dispose() {
    _suggestionController.dispose();
    super.dispose();
  }

  // ── Snack ──────────────────────────────────────────────────────────────────
  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: isError ? 3 : 2),
      ));
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _postSuggestion() async {
    final text = _suggestionController.text.trim();
    if (text.isEmpty) {
      _showSnack('Please enter a suggestion', isError: true);
      return;
    }
    if (text.length < 10) {
      _showSnack('Please write at least 10 characters', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('suggestions').add({
        'message':   text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _suggestionController.clear();
      _showSnack('Suggestion posted successfully!', isError: false);
    } catch (_) {
      _showSnack('Error posting suggestion. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    final hPad       = _cl(screenW * 0.05,  16.0, 32.0);
    final labelFontSz = _cl(screenW * 0.045, 15.0, 19.0);
    final subFontSz  = _cl(screenW * 0.035, 12.0, 14.0);
    final hintFontSz = _cl(screenW * 0.038, 13.0, 15.0);
    final btnH       = _cl(screenH * 0.07,  50.0, 62.0);
    final btnFontSz  = _cl(screenW * 0.044, 14.0, 17.0);
    final cardRadius = _cl(screenW * 0.04,  12.0, 18.0);
    final fieldLines = screenH < 600 ? 4 : 6;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Suggestions',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ── Ad banner (nearby Firestore ad → AdMob fallback) ──────────
              // LocationAdWidget handles everything:
              //   1. Checks Firestore 'ads' within 30 km & not expired
              //   2. Falls back to Google AdMob Large Banner if none found
              const LocationAdWidget(
                targetAdSize: 'Large Banner (320×100)',
              ),

              SizedBox(height: _cl(screenH * 0.03, 18.0, 30.0)),

              // ── Suggestion card ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(_cl(screenW * 0.045, 14.0, 22.0)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _lightPurple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.lightbulb_outline,
                            color: _purple,
                            size: _cl(screenW * 0.055, 18.0, 26.0)),
                      ),
                      SizedBox(width: _cl(screenW * 0.03, 10.0, 14.0)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share Your Idea',
                              style: TextStyle(
                                fontSize: labelFontSz,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'We read every suggestion carefully',
                              style: TextStyle(
                                fontSize: subFontSz,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),

                    SizedBox(height: _cl(screenH * 0.022, 14.0, 22.0)),

                    // Text field
                    TextField(
                      controller: _suggestionController,
                      maxLines: fieldLines,
                      maxLength: 500,
                      style: TextStyle(
                          fontSize: hintFontSz,
                          color: Colors.black87,
                          fontWeight: FontWeight.w400),
                      decoration: InputDecoration(
                        hintText:
                        'What would you like to see improved or added?',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: hintFontSz),
                        hintMaxLines: 2,
                        filled: true,
                        fillColor: _lightPurple,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: _purple.withOpacity(0.3), width: 1.2),
                          borderRadius: BorderRadius.circular(cardRadius),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                          const BorderSide(color: _purple, width: 1.5),
                          borderRadius: BorderRadius.circular(cardRadius),
                        ),
                        counterStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: _cl(screenW * 0.028, 9.0, 12.0)),
                      ),
                    ),

                    SizedBox(height: _cl(screenH * 0.025, 16.0, 26.0)),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: btnH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: _isLoading
                              ? LinearGradient(colors: [
                            _purple.withOpacity(0.5),
                            _deepPurple.withOpacity(0.5),
                          ])
                              : const LinearGradient(
                              colors: [_purple, _deepPurple]),
                          borderRadius: BorderRadius.circular(cardRadius),
                          boxShadow: _isLoading
                              ? []
                              : [
                            BoxShadow(
                              color: _purple.withOpacity(0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _postSuggestion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(cardRadius)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 1.8),
                          )
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Post Suggestion',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: btnFontSz,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: _cl(screenH * 0.025, 16.0, 24.0)),

              // ── Footer note ──────────────────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: _cl(screenW * 0.032, 11.0, 14.0),
                        color: Colors.grey.shade400),
                    const SizedBox(width: 5),
                    Text(
                      'Your feedback is anonymous and secure',
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: _cl(screenW * 0.03, 10.0, 12.0)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}