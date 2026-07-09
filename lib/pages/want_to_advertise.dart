import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  WantToAdvertisePage
//  Lets a seller submit an ad request with title, description, budget,
//  duration, target category, contact details, and optional banner image.
//  Data is written to Firestore → "AdRequests/{uid}/ads/{docId}"
//  Banner images are stored in Storage → "AdBanners/{uuid}.jpg"
// ─────────────────────────────────────────────────────────────────────────────

class WantToAdvertisePage extends StatefulWidget {
  const WantToAdvertisePage({Key? key}) : super(key: key);

  @override
  State<WantToAdvertisePage> createState() => _WantToAdvertisePageState();
}

class _WantToAdvertisePageState extends State<WantToAdvertisePage> {
  // ── Form ──────────────────────────────────────────────────────────────────
  final _formKey             = GlobalKey<FormState>();
  final _titleCtrl           = TextEditingController();
  final _descCtrl            = TextEditingController();
  final _budgetCtrl          = TextEditingController();
  final _contactNameCtrl     = TextEditingController();
  final _contactEmailCtrl    = TextEditingController();
  final _contactPhoneCtrl    = TextEditingController();
  final _customCategoryCtrl  = TextEditingController();

  // ── State ─────────────────────────────────────────────────────────────────
  String   _selectedDuration    = '7 days';
  String   _selectedCategory    = 'Electronics';
  XFile?   _bannerImage;
  bool     _isSubmitting        = false;
  double   _uploadProgress      = 0.0;
  bool     _showCustomCategory  = false;

  static const _durations = ['3 days', '7 days', '14 days', '30 days'];
  static const _categories = [
    'Electronics', 'Fashion', 'Home & Garden', 'Sports',
    'Books', 'Toys', 'Vehicles', 'Other',
  ];

  // ── Design tokens (mirrors AddProductPage) ────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _lightPurple = Color(0xFFF3EEFF);
  static const _green       = Color(0xFF1B8A4C);
  static const _red         = Color(0xFFB00020);
  static const _amber       = Color(0xFFF59E0B);

  double _cl(double v, double mn, double mx) =>
      v.clamp(mn, mx);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactEmailCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  // ── Snack ─────────────────────────────────────────────────────────────────
  void _snack(String msg, {required bool isError, bool isWarning = false}) {
    if (!mounted) return;
    final bg = isWarning ? _amber : (isError ? _red : _green);
    final icon = isWarning
        ? Icons.warning_amber_rounded
        : (isError ? Icons.error_outline : Icons.check_circle_outline);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: isError ? 3 : 2),
      ));
  }

  // ── Banner pick ───────────────────────────────────────────────────────────
  Future<void> _pickBanner() async {
    if (_isSubmitting) return;
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (img == null) return;
      final file = File(img.path);
      if (!await file.exists()) {
        _snack('Could not read image.', isError: true);
        return;
      }
      if (await file.length() > 10 * 1024 * 1024) {
        _snack('Image exceeds 10 MB.', isError: true);
        return;
      }
      setState(() => _bannerImage = img);
    } on Exception catch (e) {
      _snack('Image selection failed: ${_friendly(e)}', isError: true);
    }
  }

  // ── Compress ──────────────────────────────────────────────────────────────
  Future<Uint8List?> _compress(XFile img) async {
    final file = File(img.path);
    if (!await file.exists()) return null;
    return FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1280,
      minHeight: 720,
      quality: 75,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  // ── Upload banner ─────────────────────────────────────────────────────────
  Future<String?> _uploadBanner() async {
    if (_bannerImage == null) return null;
    final bytes = await _compress(_bannerImage!);
    if (bytes == null) throw Exception('Compression failed');

    final ref = FirebaseStorage.instance
        .ref()
        .child('AdBanners/${const Uuid().v4()}.jpg');
    final task = ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000',
      ),
    );

    task.snapshotEvents.listen((snap) {
      if (!mounted) return;
      setState(() => _uploadProgress =
          snap.bytesTransferred / snap.totalBytes);
    });

    await task;
    return ref.getDownloadURL();
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _snack('Please fill in the required fields.', isError: true);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('Please sign in to submit an ad request.', isError: true);
      return;
    }

    final budget = double.tryParse(_budgetCtrl.text.trim());
    if (budget == null || budget <= 0) {
      _snack('Enter a valid budget amount.', isError: true);
      return;
    }

    setState(() {
      _isSubmitting    = true;
      _uploadProgress  = 0.0;
    });

    try {
      String? bannerUrl;
      if (_bannerImage != null) {
        bannerUrl = await _uploadBanner();
      }

      final category = _showCustomCategory
          ? _customCategoryCtrl.text.trim()
          : _selectedCategory;

      await FirebaseFirestore.instance
          .collection('AdRequests')
          .doc(uid)
          .collection('ads')
          .add({
        'title':        _titleCtrl.text.trim(),
        'description':  _descCtrl.text.trim(),
        'budget':       budget,
        'duration':     _selectedDuration,
        'category':     category,
        'contactName':  _contactNameCtrl.text.trim(),
        'contactEmail': _contactEmailCtrl.text.trim(),
        'contactPhone': _contactPhoneCtrl.text.trim(),
        'bannerUrl':    bannerUrl,
        'status':       'pending',   // pending | approved | rejected
        'uid':          uid,
        'createdAt':    FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15),
          onTimeout: () =>
          throw Exception('Request timed out. Check connection.'));

      if (mounted) {
        _snack('Ad request submitted! We\'ll review it shortly.', isError: false);
        _reset();
      }
    } on FirebaseException catch (e) {
      _snack(_fbMsg(e), isError: true);
    } on SocketException {
      _snack('No internet. Please try again.', isError: true);
    } on Exception catch (e) {
      _snack('Error: ${_friendly(e)}', isError: true);
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadProgress = 0.0; });
    }
  }

  void _reset() {
    setState(() {
      _titleCtrl.clear();
      _descCtrl.clear();
      _budgetCtrl.clear();
      _contactNameCtrl.clear();
      _contactEmailCtrl.clear();
      _contactPhoneCtrl.clear();
      _customCategoryCtrl.clear();
      _bannerImage        = null;
      _selectedDuration   = '7 days';
      _selectedCategory   = 'Electronics';
      _showCustomCategory = false;
      _uploadProgress     = 0.0;
    });
  }

  String _fbMsg(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':      return 'Permission denied. Please sign in.';
      case 'storage/unauthorized':   return 'Storage access denied.';
      case 'unavailable':            return 'Service unavailable. Try again later.';
      default:                       return e.message ?? 'Unexpected error.';
    }
  }

  String _friendly(Exception e) {
    final m = e.toString();
    if (m.contains('timeout')) return 'Request timed out.';
    if (m.contains('network')) return 'Network error. Check internet.';
    return 'Something went wrong.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final sw      = mq.size.width;
    final hPad       = _cl(sw * 0.05, 16.0, 32.0);
    final cardRadius = _cl(sw * 0.04, 12.0, 18.0);
    final labelSz    = _cl(sw * 0.038, 13.0, 15.0);
    final fieldSz    = _cl(sw * 0.038, 13.0, 15.0);
    final btnH       = _cl(sw * 0.14, 50.0, 62.0);
    final btnFontSz  = _cl(sw * 0.044, 14.0, 17.0);
    final gap        = _cl(sw * 0.04, 12.0, 20.0);
    final bannerH    = _cl(sw * 0.45, 140.0, 200.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FF),
      appBar: _buildAppBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),

              // ── Hero info banner ────────────────────────────────────────
              _infoBanner(sw),
              SizedBox(height: gap),

              // ── Ad Title ────────────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Ad Title', labelSz),
                  const SizedBox(height: 8),
                  _field(
                    ctrl: _titleCtrl, hint: 'e.g. Summer Sale – 50% Off TVs',
                    fontSize: fieldSz, radius: cardRadius,
                    maxLength: 80,
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'Title must be at least 5 characters' : null,
                  ),
                ],
              )),
              SizedBox(height: gap * 0.75),

              // ── Description ─────────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Ad Description', labelSz),
                  const SizedBox(height: 8),
                  _field(
                    ctrl: _descCtrl,
                    hint: 'What do you want to promote? Describe your offer clearly.',
                    fontSize: fieldSz, radius: cardRadius, maxLines: 4,
                    maxLength: 500,
                    validator: (v) {
                      if (v == null || v.trim().length < 20)
                        return 'At least 20 characters required';
                      if (v.trim().length > 500) return 'Max 500 characters';
                      return null;
                    },
                  ),
                ],
              )),
              SizedBox(height: gap * 0.75),

              // ── Budget & Duration ────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Budget & Duration', labelSz),
                  SizedBox(height: gap * 0.6),
                  Row(children: [
                    Expanded(child: _field(
                      ctrl: _budgetCtrl,
                      hint: 'Amount (₹)',
                      label: 'Budget (₹)',
                      fontSize: fieldSz, radius: cardRadius,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final val = double.tryParse(v.trim());
                        if (val == null) return 'Invalid';
                        if (val < 100) return 'Min ₹100';
                        return null;
                      },
                    )),
                    SizedBox(width: _cl(sw * 0.03, 10.0, 16.0)),
                    Expanded(child: _dropdownField(
                      label: 'Duration',
                      value: _selectedDuration,
                      items: _durations,
                      fontSize: fieldSz,
                      radius: cardRadius,
                      onChanged: (v) => setState(() => _selectedDuration = v!),
                    )),
                  ]),
                ],
              )),
              SizedBox(height: gap * 0.75),

              // ── Category ────────────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Target Category', labelSz),
                  const SizedBox(height: 8),
                  _dropdownField(
                    label: 'Category',
                    value: _selectedCategory,
                    items: _categories,
                    fontSize: fieldSz,
                    radius: cardRadius,
                    onChanged: (v) => setState(() {
                      _selectedCategory   = v!;
                      _showCustomCategory = v == 'Other';
                      if (!_showCustomCategory) _customCategoryCtrl.clear();
                    }),
                  ),
                  if (_showCustomCategory) ...[
                    const SizedBox(height: 10),
                    _field(
                      ctrl: _customCategoryCtrl,
                      hint: 'Specify your category',
                      fontSize: fieldSz, radius: cardRadius,
                      validator: (v) => (_showCustomCategory &&
                          (v == null || v.trim().isEmpty))
                          ? 'Please specify category' : null,
                    ),
                  ],
                ],
              )),
              SizedBox(height: gap * 0.75),

              // ── Banner image ─────────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _label('Banner Image  (optional)', labelSz),
                      if (_bannerImage != null)
                        GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _bannerImage = null),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _red.withOpacity(0.3)),
                            ),
                            child: Text('Remove',
                                style: TextStyle(
                                    color: _red,
                                    fontSize: _cl(sw * 0.03, 10.0, 12.0),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _isSubmitting ? null : _pickBanner,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _bannerImage != null
                          ? _bannerPreview(bannerH, cardRadius)
                          : _bannerPlaceholder(bannerH, cardRadius, sw),
                    ),
                  ),
                  if (_isSubmitting && _bannerImage != null) ...[
                    const SizedBox(height: 12),
                    _progressBar(sw),
                  ],
                ],
              )),
              SizedBox(height: gap * 0.75),

              // ── Contact ──────────────────────────────────────────────────
              _card(cardRadius, Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Contact Details', labelSz),
                  SizedBox(height: gap * 0.6),
                  _field(
                    ctrl: _contactNameCtrl,
                    hint: 'Your full name',
                    label: 'Name',
                    fontSize: fieldSz, radius: cardRadius,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required' : null,
                  ),
                  SizedBox(height: _cl(sw * 0.03, 10.0, 14.0)),
                  _field(
                    ctrl: _contactEmailCtrl,
                    hint: 'you@example.com',
                    label: 'Email',
                    fontSize: fieldSz, radius: cardRadius,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$')
                          .hasMatch(v.trim());
                      return ok ? null : 'Enter a valid email';
                    },
                  ),
                  SizedBox(height: _cl(sw * 0.03, 10.0, 14.0)),
                  _field(
                    ctrl: _contactPhoneCtrl,
                    hint: '10-digit mobile number',
                    label: 'Phone (optional)',
                    fontSize: fieldSz, radius: cardRadius,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return v.trim().length == 10
                          ? null
                          : 'Enter a valid 10-digit number';
                    },
                  ),
                ],
              )),
              SizedBox(height: gap * 1.4),

              // ── Submit ───────────────────────────────────────────────────
              _submitBtn(btnH, btnFontSz, cardRadius),
              SizedBox(height: gap),

              // ── Disclaimer ───────────────────────────────────────────────
              Center(
                child: Text(
                  'Submissions are reviewed within 24–48 hours.\nWe\'ll contact you via the email provided.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _cl(sw * 0.03, 10.0, 12.5),
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ),
              SizedBox(height: gap),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() => AppBar(
    scrolledUnderElevation: 0,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    title: const Text(
      'Want to Advertise?',
      style: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3),
    ),
    leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.black, size: 18),
        onPressed: () {
          Navigator.pop(context);
        }
    ),
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
    ),
  );

  // ── Info banner ───────────────────────────────────────────────────────────
  Widget _infoBanner(double sw) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF7B2FFF), Color(0xFF2D0050)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(_cl(sw * 0.04, 12.0, 18.0)),
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.campaign_outlined, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reach thousands of buyers',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: _cl(sw * 0.04, 13.0, 15.5),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Fill in the details below and our team will set up your ad.',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: _cl(sw * 0.032, 11.0, 13.0),
                  height: 1.4)),
        ]),
      ),
    ]),
  );

  // ── Banner preview ────────────────────────────────────────────────────────
  Widget _bannerPreview(double h, double r) => Container(
    key: const ValueKey('preview'),
    height: h,
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: _purple.withOpacity(0.25), width: 1.5),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Stack(fit: StackFit.expand, children: [
        Image.file(File(_bannerImage!.path), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
                color: Colors.grey)),
        Positioned(
          bottom: 8, right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_outlined, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Text('Change', style: TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    ),
  );

  // ── Banner placeholder ────────────────────────────────────────────────────
  Widget _bannerPlaceholder(double h, double r, double sw) => Container(
    key: const ValueKey('placeholder'),
    height: h,
    width: double.infinity,
    decoration: BoxDecoration(
      color: _lightPurple,
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: _purple.withOpacity(0.25), width: 1.5),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.add_photo_alternate_outlined,
          size: _cl(sw * 0.1, 30.0, 46.0),
          color: _purple.withOpacity(0.4)),
      const SizedBox(height: 8),
      Text('Tap to add a banner image',
          style: TextStyle(color: _purple.withOpacity(0.6),
              fontSize: _cl(sw * 0.032, 11.0, 13.0),
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      Text('Recommended: 1280 × 720 px · Max 10 MB',
          style: TextStyle(color: _purple.withOpacity(0.4),
              fontSize: _cl(sw * 0.028, 9.5, 11.5))),
    ]),
  );

  // ── Progress bar ──────────────────────────────────────────────────────────
  Widget _progressBar(double sw) => Row(children: [
    Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _uploadProgress,
          minHeight: 7,
          backgroundColor: Colors.grey.shade200,
          valueColor: const AlwaysStoppedAnimation<Color>(_purple),
        ),
      ),
    ),
    const SizedBox(width: 10),
    Text('${(_uploadProgress * 100).toStringAsFixed(0)}%',
        style: TextStyle(
            fontSize: _cl(sw * 0.03, 10.0, 13.0),
            color: _purple,
            fontWeight: FontWeight.w600)),
  ]);

  // ── Submit button ─────────────────────────────────────────────────────────
  Widget _submitBtn(double h, double fontSize, double radius) => SizedBox(
    width: double.infinity,
    height: h,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: _isSubmitting
            ? LinearGradient(colors: [
          _purple.withOpacity(0.5),
          _deepPurple.withOpacity(0.5)
        ])
            : const LinearGradient(colors: [_purple, _deepPurple]),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: _isSubmitting
            ? []
            : [BoxShadow(color: _purple.withOpacity(0.35),
            blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
        child: _isSubmitting
            ? const SizedBox(height: 22, width: 22,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 1.8))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text('Submit Ad Request',
              style: TextStyle(fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white, letterSpacing: 0.3)),
        ]),
      ),
    ),
  );

  // ── Section card ──────────────────────────────────────────────────────────
  Widget _card(double r, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(r),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: child,
  );

  // ── Label ─────────────────────────────────────────────────────────────────
  Widget _label(String text, double sz) => Text(text,
      style: TextStyle(fontWeight: FontWeight.w600,
          fontSize: sz, color: Colors.black87));

  // ── Dropdown ──────────────────────────────────────────────────────────────
  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> items,
    required double fontSize,
    required double radius,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: Colors.black87),
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          color: Color(0xFF6A00FF)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: fontSize * 0.9,
            fontWeight: FontWeight.w500),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: _purple.withOpacity(0.5))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide:
            const BorderSide(color: Color(0xFFDDD8FF), width: 1)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: _purple, width: 1.5)),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
    );
  }

  // ── Text field ────────────────────────────────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required double fontSize,
    required double radius,
    String? label,
    int maxLines = 1,
    int? maxLength,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      validator: validator,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: fontSize * 0.9,
            fontWeight: FontWeight.w500),
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: fontSize,
            fontWeight: FontWeight.normal),
        counterText: '',
        filled: true,
        fillColor: readOnly ? Colors.grey.shade50 : Colors.white,
        contentPadding: EdgeInsets.symmetric(
            horizontal: 14, vertical: maxLines > 1 ? 14 : 0),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: _purple.withOpacity(0.5))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: Color(0xFFDDD8FF), width: 1)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: _purple, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: _red, width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: _red, width: 1.5)),
      ),
    );
  }
}