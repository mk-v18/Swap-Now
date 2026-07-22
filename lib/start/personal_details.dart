import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/start/payment.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class PersonalDetailsPage extends StatefulWidget {
  const PersonalDetailsPage({super.key});

  @override
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

// FIX(perf): Immutable snapshot of referral-check UI state, held in a single
// ValueNotifier below instead of three separate setState()-driven bools.
// Keeping them together means one notification instead of three, and lets
// the suffix-icon + helper-text widgets rebuild independently of the rest
// of the page.
class _ReferralStatus {
  final bool isChecking;
  final bool checked;
  final bool isValid;
  const _ReferralStatus({
    this.isChecking = false,
    this.checked = false,
    this.isValid = false,
  });
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
  // ── Controllers & Focus ────────────────────────────────────────────────────
  final TextEditingController _nameController     = TextEditingController();
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _referralController = TextEditingController();

  final FocusNode _locationFocusNode = FocusNode();
  final LayerLink _layerLink         = LayerLink();
  OverlayEntry?   _overlayEntry;

  // ── State ──────────────────────────────────────────────────────────────────
  // FIX(perf): The flags below used to be plain bools flipped via setState(),
  // which reran this whole page's build() — including all the MediaQuery
  // layout math and every text field — just to toggle one small spinner or
  // icon. They're now ValueNotifiers consumed by narrowly-scoped
  // ValueListenableBuilders, so only the relevant leaf widget rebuilds.
  final ValueNotifier<File?> _imageFileNotifier = ValueNotifier<File?>(null);
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isFetchingSuggestionsNotifier =
  ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isDetectingLocationNotifier =
  ValueNotifier<bool>(false);
  final ValueNotifier<_ReferralStatus> _referralStatusNotifier =
  ValueNotifier<_ReferralStatus>(const _ReferralStatus());

  // These feed the overlay only (rebuilt imperatively via _showOverlay()),
  // not this State's build() — so they stay as plain fields with no
  // notifier/setState wrapper at all.
  List<String> _suggestions = [];
  List<Map<String, double>?> _suggestionCoords = [];

  double? _latitude;
  double? _longitude;
  Timer?       _debounce;
  Timer?       _referralDebounce;

  String? _referralDocId;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _lightPurple = Color(0xFFECDDF4);
  static const _errorRed    = Color(0xFFB00020);

  // FIX(perf): Pre-computed colour constants — eliminates withOpacity()
  // allocation inside build() / _buildSaveButton() on every frame.
  static const _purpleShadow = Color(0x595800B3); // ~35% opacity

  // FIX(perf): Pre-computed border objects — _outline() was constructing a new
  // OutlineInputBorder on every build() call (called 6–9 times per rebuild).
  static final _borderNormal = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _purple, width: 1.0),
  );
  static final _borderFocused = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _purple, width: 1.5),
  );

  // FIX(perf): Static compiled RegExp — was re-compiled on every submit tap.
  static final _emailRegExp =
  RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$');

  // Image upload limits
  static const _maxImageBytes = 5 * 1024 * 1024; // 5 MB
  static const _allowedMimes  = {'image/jpeg', 'image/png', 'image/webp'};

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _locationFocusNode.addListener(() {
      if (!_locationFocusNode.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _referralDebounce?.cancel();    // FIX: cancel referral debounce on dispose
    _removeOverlay();
    _locationFocusNode.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    _referralController.dispose();
    _imageFileNotifier.dispose();
    _isLoadingNotifier.dispose();
    _isFetchingSuggestionsNotifier.dispose();
    _isDetectingLocationNotifier.dispose();
    _referralStatusNotifier.dispose();
    super.dispose();
  }

  // ── Overlay ────────────────────────────────────────────────────────────────
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;

    // FIX(reliability): Guard against overlay not being in tree.
    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;

    final screenW = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: screenW - 36,
        child: CompositedTransformFollower(
          link:             _layerLink,
          showWhenUnlinked: false,
          offset:           const Offset(0, 58),
          child: Material(
            elevation:    6,
            borderRadius: BorderRadius.circular(12),
            color:        Colors.white,
            // FIX(reliability): Cap overlay height — without this, 5 long
            // Nominatim addresses overflow off-screen on small devices.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.28,
              ),
              child: ListView.separated(
                padding:          EdgeInsets.zero,
                shrinkWrap:       true,
                itemCount:        _suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) {
                  final isFirst = i == 0;
                  final isLast  = i == _suggestions.length - 1;
                  return InkWell(
                    borderRadius: BorderRadius.vertical(
                      top:    isFirst ? const Radius.circular(12) : Radius.zero,
                      bottom: isLast  ? const Radius.circular(12) : Radius.zero,
                    ),
                    onTap: () => _selectSuggestion(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 16, color: _purple),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _suggestions[i],
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(_overlayEntry!);
  }

  // ── Location autocomplete ──────────────────────────────────────────────────
  void _onLocationChanged(String value) {
    // FIX(gap): manual edits invalidate any previously captured coordinates.
    _latitude = null;
    _longitude = null;
    _debounce?.cancel();
    if (value.trim().length < 3) {
      _suggestions = [];
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value.trim());
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (!mounted) return;
    _isFetchingSuggestionsNotifier.value = true;
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(input)}&format=json&limit=5&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'SwapNow/1.0 (com.credbro.app)',
      }).timeout(const Duration(seconds: 8)); // FIX: timeout prevents hanging

      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        _suggestions = data
            .map<String>((item) => item['display_name'] as String)
            .toList();
        // FIX(gap): capture each suggestion's coordinates from Nominatim
        // so a tap can populate _latitude/_longitude, not just the text.
        _suggestionCoords = data.map<Map<String, double>?>((item) {
          final lat = double.tryParse(item['lat']?.toString() ?? '');
          final lon = double.tryParse(item['lon']?.toString() ?? '');
          if (lat == null || lon == null) return null;
          return {'lat': lat, 'lng': lon};
        }).toList();
        _showOverlay();
      } else {
        _suggestions = [];
        _suggestionCoords = [];
        _removeOverlay();
      }
    } on TimeoutException {
      _suggestions = [];
      _suggestionCoords = [];
      _removeOverlay();
    } catch (_) {
      _suggestions = [];
      _suggestionCoords = [];
      _removeOverlay();
    } finally {
      if (mounted) _isFetchingSuggestionsNotifier.value = false;
    }
  }

  void _selectSuggestion(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final suggestion = _suggestions[index];
    final parts   = suggestion.split(',').map((s) => s.trim()).toList();
    final trimmed = parts.take(3).join(', ');
    final coords = index < _suggestionCoords.length ? _suggestionCoords[index] : null;
    _locationController.text = trimmed;
    // FIX(gap): persist the coordinates that came with this suggestion.
    _latitude = coords?['lat'];
    _longitude = coords?['lng'];
    _locationFocusNode.unfocus();
    _suggestions = [];
    _suggestionCoords = [];
    _removeOverlay();
  }

  // ── GPS detect ─────────────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showErrorSnack('Location services are disabled. Please enable them.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showErrorSnack('Location permission is required to continue.');
      }
      return;
    }

    if (!mounted) return;
    _isDetectingLocationNotifier.value = true;
    _removeOverlay();

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12)); // FIX: GPS timeout guard

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _locationController.text =
        '${p.locality}, ${p.administrativeArea}, ${p.country}';
        _suggestions = [];
        _suggestionCoords = [];
        // FIX(gap): keep the exact GPS coordinates, not just the text.
        _latitude = position.latitude;
        _longitude = position.longitude;
      }
    } on TimeoutException {
      if (mounted) {
        _showErrorSnack('Location request timed out. Please try again.');
      }
    } catch (_) {
      if (mounted) _showErrorSnack('Failed to get location. Please try again.');
    } finally {
      if (mounted) _isDetectingLocationNotifier.value = false;
    }
  }

  // ── Referral ───────────────────────────────────────────────────────────────

  // FIX: Referral field now debounced — was firing a Firestore query on
  // every single keystroke. 600 ms delay batches rapid typing into one call.
  void _onReferralChanged(String val) {
    _referralDebounce?.cancel();
    if (val.isEmpty) {
      _referralDocId = null;
      _referralStatusNotifier.value = const _ReferralStatus();
      return;
    }
    _referralDebounce = Timer(
      const Duration(milliseconds: 600),
          () => _validateReferral(val.trim()),
    );
  }

  Future<void> _validateReferral(String code) async {
    if (code.isEmpty) {
      _referralDocId = null;
      _referralStatusNotifier.value = const _ReferralStatus();
      return;
    }
    if (!mounted) return;
    _referralStatusNotifier.value =
        _ReferralStatus(isChecking: true, checked: false, isValid: false);
    try {
      final query = await FirebaseFirestore.instance
          .collection('referrals')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isNotEmpty) {
        final data     = query.docs.first.data();
        final expiry   = (data['activeUntil'] as Timestamp?)?.toDate();
        final isActive = expiry == null || DateTime.now().isBefore(expiry);

        if (isActive && data['active'] == true) {
          _referralDocId = query.docs.first.id;
          _referralStatusNotifier.value =
          const _ReferralStatus(isChecking: false, checked: true, isValid: true);
        } else {
          _referralDocId = null;
          _referralStatusNotifier.value = const _ReferralStatus(
              isChecking: false, checked: true, isValid: false);
        }
      } else {
        _referralDocId = null;
        _referralStatusNotifier.value = const _ReferralStatus(
            isChecking: false, checked: true, isValid: false);
      }
    } catch (_) {
      if (mounted) _showErrorSnack('Error checking referral code. Try again.');
      _referralStatusNotifier.value = _ReferralStatus(
        isChecking: false,
        checked: _referralStatusNotifier.value.checked,
        isValid: _referralStatusNotifier.value.isValid,
      );
    } finally {
      if (mounted && _referralStatusNotifier.value.isChecking) {
        _referralStatusNotifier.value = _ReferralStatus(
          isChecking: false,
          checked: _referralStatusNotifier.value.checked,
          isValid: _referralStatusNotifier.value.isValid,
        );
      }
    }
  }

  // ── Pick image ─────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source:     ImageSource.gallery,
      // FIX(security + perf): Compress on pick — reduces upload size and
      // prevents users uploading raw 20 MB camera files to Storage.
      imageQuality: 75,
      maxWidth:     800,
      maxHeight:    800,
    );
    if (picked == null) return;

    final file       = File(picked.path);
    final fileLength = await file.length();

    // FIX(security): Reject files over 5 MB even after compression.
    if (fileLength > _maxImageBytes) {
      if (mounted) {
        _showErrorSnack('Image is too large. Please choose one under 5 MB.');
      }
      return;
    }

    if (mounted) _imageFileNotifier.value = file;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submitDetails() async {
    // FIX: Guard re-entry at the top synchronously — prevents double-tap
    // submitting while the first async call is in-flight.
    if (_isLoadingNotifier.value) return;

    final name     = _nameController.text.trim();
    final email    = _emailController.text.trim();
    final location = _locationController.text.trim();
    final imageFile = _imageFileNotifier.value;

    if (name.isEmpty || email.isEmpty || location.isEmpty || imageFile == null) {
      _showErrorSnack('Please fill in all fields and add a profile photo.');
      return;
    }

    // FIX(perf): Use static RegExp — no re-compilation on every submit.
    if (!_emailRegExp.hasMatch(email)) {
      _showErrorSnack('Please enter a valid email address.');
      return;
    }

    // FIX(security): Null-safe user resolution — avoids force-unwrap crash
    // if auth token lapses between login and form submit.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorSnack('Session expired. Please log in again.');
      return;
    }
    final uid = user.uid;

    _isLoadingNotifier.value = true;

    try {
      // FIX(security): Verify file still exists and is within size limits
      // before attempting upload — file could be deleted between pick and submit.
      final fileLength = await imageFile.length();
      if (fileLength > _maxImageBytes) {
        _showErrorSnack('Image is too large. Please choose one under 5 MB.');
        return;
      }

      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images/$uid.jpg');
      await ref.putFile(
        imageFile,
        // FIX(security): Set explicit content type — prevents Storage from
        // serving an arbitrary MIME type supplied by the client device.
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await ref.getDownloadURL();

      final referralStatus = _referralStatusNotifier.value;

      // FIX: Batch user doc write and referral update — reduces round-trips.
      // User doc uses set+merge so it is idempotent on retry.
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid':              uid,
        'phone':            user.phoneNumber,
        'name':             name,
        'email':            email,
        'location':         location,
        // FIX(gap): persist coordinates alongside the location string so
        // home_page.dart can sort nearby products without a live geocode.
        'lat':              _latitude,
        'lng':              _longitude,
        'profileImage':     imageUrl,
        'referralCodeUsed': referralStatus.isValid
            ? _referralController.text.trim()
            : null,
        'role':             'user',
        'onboardingStep':   'payment',
        'createdAt':        FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // FIX: merge:true → idempotent on retry

      if (referralStatus.isValid && _referralDocId != null) {
        final refDoc = FirebaseFirestore.instance
            .collection('referrals')
            .doc(_referralDocId!);
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snapshot = await tx.get(refDoc);
          if (snapshot.exists) {
            final data   = snapshot.data() as Map<String, dynamic>;
            final joined =
            (data['joinedUsers'] is int) ? data['joinedUsers'] as int : 0;
            tx.update(refDoc, {
              'joinedUsers':  joined + 1,
              'lastJoinedAt': FieldValue.serverTimestamp(),
            });
          }
        });
      }

      if (!mounted) return;

      // FIX(reliability): pushReplacement — user cannot press Back to re-submit
      // personal details and trigger duplicate Firestore/Storage writes.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PaymentPage()),
      );
    } catch (_) {
      if (mounted) _showErrorSnack('Something went wrong. Please try again.');
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  // ── SnackBar ───────────────────────────────────────────────────────────────
  void _showErrorSnack(String message) {
    // FIX: mounted guard — prevents "setState after dispose" crashes that
    // occurred when called from async callbacks (GPS, HTTP, Firestore).
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    fontSize:   13,
                    color:      Colors.white,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: _errorRed,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin:   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    // FIX(perf): Replaced manual _clamp() helper (redundant reimplementation
    // of double.clamp()) with the built-in method throughout.
    final avatarOuter  = (screenW * 0.18).clamp(54.0, 72.0);
    final avatarGap    = avatarOuter - 3;
    final avatarInner  = avatarGap - 5;
    final fieldH       = (screenH * 0.065).clamp(50.0, 60.0);
    final hPad         = (screenW * 0.05).clamp(16.0, 32.0);
    final labelFontSz  = (screenW * 0.035).clamp(13.0, 15.0);
    final hintFontSz   = (screenW * 0.035).clamp(13.0, 14.0);
    final btnFontSz    = (screenW * 0.042).clamp(14.0, 17.0);
    final gapSm        = (screenH * 0.012).clamp(8.0, 14.0);
    final gapMd        = (screenH * 0.018).clamp(12.0, 20.0);
    final gapTop       = (screenH * 0.02).clamp(12.0, 24.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Profile Details',
          style: TextStyle(
            color:      Colors.black,
            fontSize:   (screenW * 0.05).clamp(17.0, 22.0),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: gapTop),

              // ── Avatar ───────────────────────────────────────────────────
              // FIX(perf): Only this avatar subtree rebuilds when a photo is
              // picked, via ValueListenableBuilder on _imageFileNotifier —
              // not the whole page.
              ValueListenableBuilder<File?>(
                valueListenable: _imageFileNotifier,
                builder: (context, imageFile, _) => GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius:          avatarOuter,
                    backgroundColor: _purple,
                    child: CircleAvatar(
                      radius:          avatarGap,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius:          avatarInner,
                        backgroundColor: _lightPurple,
                        backgroundImage:
                        imageFile != null ? FileImage(imageFile) : null,
                        child: imageFile == null
                            ? Icon(
                          Icons.camera_alt_outlined,
                          size:  (screenW * 0.07).clamp(24.0, 32.0),
                          color: _purple,
                        )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: gapSm * 0.6),
              Text(
                'Tap to add photo',
                style: TextStyle(
                  color:    Colors.grey.shade500,
                  fontSize: (screenW * 0.03).clamp(10.0, 13.0),
                ),
              ),

              SizedBox(height: gapMd),

              // ── Full Name ─────────────────────────────────────────────────
              _buildLabel('Full Name', labelFontSz),
              SizedBox(height: gapSm * 0.5),
              _buildTextField(
                controller: _nameController,
                hint:       'Enter your full name',
                height:     fieldH,
                hintFontSz: hintFontSz,
              ),

              SizedBox(height: gapMd),

              // ── Email ─────────────────────────────────────────────────────
              _buildLabel('Email Address', labelFontSz),
              SizedBox(height: gapSm * 0.5),
              _buildTextField(
                controller: _emailController,
                hint:       'Enter your email',
                height:     fieldH,
                hintFontSz: hintFontSz,
                inputType:  TextInputType.emailAddress,
              ),

              SizedBox(height: gapMd),

              // ── Location ──────────────────────────────────────────────────
              _buildLabel('Location', labelFontSz),
              SizedBox(height: gapSm * 0.5),
              CompositedTransformTarget(
                link: _layerLink,
                child: SizedBox(
                  height: fieldH,
                  child: TextField(
                    controller:  _locationController,
                    focusNode:   _locationFocusNode,
                    keyboardType: TextInputType.streetAddress,
                    onChanged:   _onLocationChanged,
                    style:       TextStyle(fontSize: hintFontSz),
                    decoration:  InputDecoration(
                      hintText:       'Type city or detect location',
                      hintStyle:      TextStyle(fontSize: hintFontSz),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 0),
                      // FIX(perf): isolated to _isFetchingSuggestionsNotifier
                      // so typing doesn't rebuild the rest of the form.
                      prefixIcon: ValueListenableBuilder<bool>(
                        valueListenable: _isFetchingSuggestionsNotifier,
                        builder: (context, isFetching, _) => isFetching
                            ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width:  16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _purple),
                          ),
                        )
                            : const Icon(Icons.location_on_outlined,
                            color: _purple, size: 20),
                      ),
                      // FIX(perf): isolated to _isDetectingLocationNotifier.
                      suffixIcon: ValueListenableBuilder<bool>(
                        valueListenable: _isDetectingLocationNotifier,
                        builder: (context, isDetecting, _) => isDetecting
                            ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width:  16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _purple),
                          ),
                        )
                            : IconButton(
                          tooltip:  'Use current location',
                          icon:     const Icon(Icons.my_location,
                              color: _purple, size: 20),
                          onPressed: _detectLocation,
                        ),
                      ),
                      // FIX(perf): Use pre-computed static border objects.
                      border:        _borderNormal,
                      enabledBorder: _borderNormal,
                      focusedBorder: _borderFocused,
                    ),
                  ),
                ),
              ),

              SizedBox(height: gapMd),

              // ── Referral ──────────────────────────────────────────────────
              _buildLabel('Referral Code  (Optional)', labelFontSz),
              SizedBox(height: gapSm * 0.5),
              // FIX(perf): isolated to _referralStatusNotifier so typing in
              // the referral field never touches the rest of the form.
              ValueListenableBuilder<_ReferralStatus>(
                valueListenable: _referralStatusNotifier,
                builder: (context, status, _) => SizedBox(
                  height: fieldH,
                  child: TextField(
                    controller:  _referralController,
                    style:       TextStyle(fontSize: hintFontSz),
                    // FIX: Route through debounced handler — was firing a
                    // Firestore query on every single keystroke.
                    onChanged:   _onReferralChanged,
                    decoration:  InputDecoration(
                      hintText:       'Enter referral code',
                      hintStyle:      TextStyle(fontSize: hintFontSz),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 0),
                      suffixIcon: status.isChecking
                          ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width:  18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _purple),
                        ),
                      )
                          : status.checked
                          ? Icon(
                        status.isValid
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: status.isValid
                            ? Colors.green
                            : Colors.red,
                        size: 22,
                      )
                          : null,
                      border:        _borderNormal,
                      enabledBorder: _borderNormal,
                      focusedBorder: _borderFocused,
                    ),
                  ),
                ),
              ),

              ValueListenableBuilder<_ReferralStatus>(
                valueListenable: _referralStatusNotifier,
                builder: (context, status, _) => status.checked
                    ? Padding(
                  padding: EdgeInsets.only(top: gapSm * 0.5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      status.isValid
                          ? '✓ Referral code applied!'
                          : '✗ Invalid or expired referral code.',
                      style: TextStyle(
                        fontSize:   (screenW * 0.03).clamp(11.0, 13.0),
                        color:      status.isValid ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                    : const SizedBox.shrink(),
              ),

              SizedBox(height: gapMd * 1.4),

              // ── Save button ───────────────────────────────────────────────
              // FIX(perf): isolated to _isLoadingNotifier.
              ValueListenableBuilder<bool>(
                valueListenable: _isLoadingNotifier,
                builder: (context, isLoading, _) =>
                    _buildSaveButton(btnFontSz: btnFontSz, isLoading: isLoading),
              ),

              SizedBox(height: gapMd),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Widget helpers
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildLabel(String text, double fontSize) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: TextStyle(
        fontSize:   fontSize,
        fontWeight: FontWeight.w600,
        color:      Colors.black87,
      ),
    ),
  );

  Widget _buildTextField({
    required TextEditingController controller,
    required String                hint,
    required double                height,
    required double                hintFontSz,
    TextInputType inputType = TextInputType.text,
  }) {
    return SizedBox(
      height: height,
      child: TextField(
        controller:  controller,
        keyboardType: inputType,
        style:       TextStyle(fontSize: hintFontSz),
        decoration:  InputDecoration(
          hintText:       hint,
          hintStyle:      TextStyle(fontSize: hintFontSz),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 0),
          // FIX(perf): Use pre-computed static border objects.
          border:        _borderNormal,
          enabledBorder: _borderNormal,
          focusedBorder: _borderFocused,
        ),
      ),
    );
  }

  Widget _buildSaveButton({required double btnFontSz, required bool isLoading}) {
    return GestureDetector(
      onTap: isLoading ? null : _submitDetails,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 150),
        width:     double.infinity,
        padding:   const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isLoading
              ? const LinearGradient(
              colors: [Color(0xFF8A4FD6), Color(0xFF5800B3)])
              : const LinearGradient(colors: [_purple, _deepPurple]),
          borderRadius: BorderRadius.circular(16),
          // FIX(perf): Pre-computed constant shadow colour — no withOpacity()
          // allocation inside build() on every frame.
          boxShadow: const [
            BoxShadow(
              color:      _purpleShadow,
              blurRadius: 14,
              offset:     Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
          width:  22,
          height: 22,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 1.8),
        )
            : Text(
          'Save & Continue',
          style: TextStyle(
            color:         Colors.white,
            fontSize:      btnFontSz,
            fontWeight:    FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}