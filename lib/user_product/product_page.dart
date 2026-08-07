import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:amoeba/start/payment_success.dart';
import 'package:amoeba/start/payment_fail.dart';

// ─── Responsive Layout Helper ─────────────────────────────────────────────────
class _RL {
  final double w;
  const _RL(this.w);

  bool get isMobile  => w < 600;
  bool get isTablet  => w >= 600 && w < 1024;
  bool get isDesktop => w >= 1024;

  EdgeInsets get scrollPadding {
    if (isDesktop) return EdgeInsets.symmetric(horizontal: w * 0.18, vertical: 20);
    if (isTablet)  return const EdgeInsets.symmetric(horizontal: 36, vertical: 16);
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  }

  double get appBarFontSize  => isDesktop ? 22.0 : isTablet ? 20.0 : 18.0;
  double get labelFontSize   => isDesktop ? 14.5 : isTablet ? 14.0 : 13.5;
  double get fieldFontSize   => isDesktop ? 14.5 : isTablet ? 14.0 : 13.5;
  double get fieldRadius     => isDesktop ? 14.0 : isTablet ? 13.0 : 12.0;
  double get cardRadius      => isDesktop ? 20.0 : isTablet ? 18.0 : 16.0;
  double get cardPad         => isDesktop ? 22.0 : isTablet ? 18.0 : 16.0;
  double get sectionGap      => isDesktop ? 16.0 : isTablet ? 14.0 : 12.0;
  double get rowGap          => isDesktop ? 14.0 : isTablet ? 12.0 : 10.0;

  EdgeInsets get fieldContentPadding {
    if (isDesktop) return const EdgeInsets.symmetric(horizontal: 14, vertical: 15);
    if (isTablet)  return const EdgeInsets.symmetric(horizontal: 13, vertical: 14);
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 13);
  }

  double get thumbSize     => isDesktop ? 120.0 : isTablet ? 104.0 : 88.0;
  double get thumbSpacing  => isDesktop ? 12.0  : isTablet ? 10.0  : 9.0;
  double get thumbRadius   => isDesktop ? 12.0  : isTablet ? 11.0  : 10.0;

  double get saveButtonHeight    => isDesktop ? 60.0 : isTablet ? 56.0 : 52.0;
  double get saveButtonRadius    => isDesktop ? 18.0 : isTablet ? 16.0 : 14.0;
  double get saveButtonFontSize  => isDesktop ? 16.5 : isTablet ? 16.0 : 15.0;

  double get overlayWidth {
    if (isDesktop) return w - w * 0.36;
    if (isTablet)  return w - 72;
    return w - 32;
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────
const Color _kPurple      = Color(0xFF6A00FF);
const Color _kPurpleDark  = Color(0xFF2D0050);
const Color _kPurpleLight = Color(0xFFF3EAFF);
const Color _kBg          = Color(0xFFFFFFFF);
const Color _kBorder      = Color(0xFFE8E0FF);
const Color _kLabel       = Color(0xFF1A0040);
const Color _kSubtext     = Color(0xFF7B6FA0);
const Color _kCardBg      = Colors.white;

const List<String> _kCategories = [
  'Books', 'Courses', 'Laptops', 'Mobile Phones', 'Electronics',
  'Vehicles', 'Cycles', 'Kitchen', 'Home Decor', 'Toys',
  'Sports & Fitness', 'Plants & Gardening', 'Pets & Pet Items',
  'Furniture', 'Agriculture Equipment', 'Tools & Hardware',
  'Automotive', 'Clothes', 'Personal Care & Beauty',
  'Musical Instruments', 'Paints', 'Other',
];

const List<String> _kConditions = [
  'New', 'Like New', 'Good', 'Fair', 'Poor',
];

const int    _kMaxImages      = 3;
const String _kNominatimBase  = 'https://nominatim.openstreetmap.org/search';
const int    _kCompressQuality= 65;
const int    _kCompressMaxDim = 1024;
const int    _kSuggestionCacheCap = 40;

// ─── Listing publish fee ───────────────────────────────────────────────────
// Two ways to unlock Publish, offered in a dialog every time the signed-in
// user does NOT already have `hasLifetimeListingAccess` on their user doc:
//   • Lifetime  — flat ₹49 once. On verified payment the server sets
//                 hasLifetimeListingAccess, so every future listing skips
//                 this dialog entirely.
//   • Per-listing — 20% of the price the user is asking for THIS item,
//                 capped at ₹100. Charged again on every future listing.
// The actual charged amount is always computed server-side in
// functions/index.js (createListingOrder) from these same numbers — this
// copy is for showing the user an accurate preview before checkout opens,
// never for deciding what Razorpay actually charges.
const double _kLifetimeFeeRupees        = 49.0;
const double _kPerListingFeeRate        = 0.20;
const double _kPerListingFeeCapRupees   = 100.0;
const double _kPerListingFeeMinRupees   = 1.0; // Razorpay's own order minimum

enum _ListingFeeType { lifetime, perListing }

// Razorpay's `key_id` is publishable, not a secret — see the identical
// pattern (and reasoning) in start/payment.dart. Kept as its own fallback
// here so this page has no compile-time dependency on that screen.
const String _kRazorpayKeyFallback = 'rzp_test_TBJCKQmpFKyNl6'; // TODO: keep in sync with start/payment.dart

/// Cached autocomplete result for a given query string.
class _SuggestionResult {
  final List<String> names;
  final List<Map<String, double>?> coords;
  const _SuggestionResult(this.names, this.coords);
}

// ─── Page ─────────────────────────────────────────────────────────────────────
class UserProductListingPage extends StatefulWidget {
  const UserProductListingPage({super.key});

  @override
  State<UserProductListingPage> createState() => _UserProductListingPageState();
}

class _UserProductListingPageState extends State<UserProductListingPage> {
  // ── Controllers ──────────────────────────────────────────────────────────
  final TextEditingController _titleController       = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController        = TextEditingController();
  final TextEditingController _locationController    = TextEditingController();

  final FocusNode _locationFocusNode = FocusNode();
  final LayerLink _layerLink         = LayerLink();
  OverlayEntry?   _overlayEntry;

  // ── Form state ───────────────────────────────────────────────────────────
  String? _category;
  String? _condition;
  String  _location = '';

  // FIX(gap): coordinates were fetched via GPS but never stored/saved, and
  // suggestion taps never carried coordinates at all. Without these, the
  // home page has no lat/lng to sort by and must live-geocode the location
  // string on every load — which silently fails for some listings and
  // makes them vanish from the grid (stuck at distance = 9999).
  double? _latitude;
  double? _longitude;

  // ── Images ───────────────────────────────────────────────────────────────
  List<XFile> _images = [];
  // FIX(perf): caches the in-flight compression Future itself, not just the
  // finished bytes. Previously, if Publish was tapped before background
  // precompression finished, _uploadSingleImage found no cache entry and
  // ran a second full native compression pass on the same image in
  // parallel with the first — every image was potentially compressed
  // twice. Now both call sites await the same Future.
  final Map<String, Future<Uint8List?>> _compressedCache = {};

  // ── Flags ────────────────────────────────────────────────────────────────
  bool _isSubmitting        = false;
  bool _isDetectingLocation = false;

  // ── Autocomplete ─────────────────────────────────────────────────────────
  List<String> _suggestions           = [];
  // FIX(gap): parallel list carrying each suggestion's coordinates so a tap
  // can populate _latitude/_longitude instead of discarding them.
  List<Map<String, double>?> _suggestionCoords = [];
  Timer?       _debounce;
  bool         _isFetchingSuggestions = false;

  // FIX(perf/bug): monotonically increasing id for the current in-flight
  // autocomplete request. The old code used an "only one request at a
  // time" boolean gate, which silently dropped the latest keystroke's
  // query whenever a prior request was still waiting on a slow network.
  // Requests are now allowed to overlap; only the response whose id
  // matches the most recent request is ever applied, so a slow response
  // for an old query can no longer clobber a newer one on screen.
  int _suggestionRequestId = 0;

  // FIX(perf): per-session cache of resolved queries, so retyping
  // something already searched (very common — type, backspace, retype)
  // skips the network call entirely instead of re-hitting Nominatim.
  final Map<String, _SuggestionResult> _suggestionCache = {};

  final http.Client _httpClient = http.Client();
  final ImagePicker _picker     = ImagePicker();

  // ── Listing fee payment ───────────────────────────────────────────────────
  late final Razorpay _razorpay;
  // Resolved once in initState — Remote Config value if available, else the
  // hardcoded fallback. Same reasoning as start/payment.dart: never read
  // _kRazorpayKeyFallback directly anywhere else.
  String _razorpayKey = _kRazorpayKeyFallback;
  // Bridges Razorpay's global event-callback API to the single in-flight
  // checkout this page ever opens at a time (one per Publish attempt).
  _ListingFeeType? _pendingFeeType;
  int? _pendingAmountPaise;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _locationFocusNode.addListener(_onLocationFocusChange);

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleListingPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleListingPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleListingExternalWallet);
    _loadRazorpayKey();
  }

  Future<void> _loadRazorpayKey() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await remoteConfig.setDefaults({'razorpay_key_id': _kRazorpayKeyFallback});
      await remoteConfig.fetchAndActivate();
      final fetched = remoteConfig.getString('razorpay_key_id');
      if (fetched.isNotEmpty && mounted) _razorpayKey = fetched;
    } catch (e) {
      debugPrint('Remote Config fetch failed, using fallback Razorpay key: $e');
    }
  }

  void _onLocationFocusChange() {
    if (!_locationFocusNode.hasFocus) _removeOverlay();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _httpClient.close();
    _removeOverlay();
    _razorpay.clear();
    _locationFocusNode
      ..removeListener(_onLocationFocusChange)
      ..dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ── Overlay ──────────────────────────────────────────────────────────────
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(_RL rl) {
    _removeOverlay();
    if (_suggestions.isEmpty) return;
    if (!mounted) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: rl.overlayWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(rl.fieldRadius + 2),
            color: Colors.white,
            shadowColor: _kPurple.withOpacity(0.15),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rl.fieldRadius + 2),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length.clamp(0, 5),
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) {
                  final isFirst = i == 0;
                  final isLast  = i == _suggestions.length - 1;
                  return InkWell(
                    borderRadius: BorderRadius.vertical(
                      top:    isFirst ? Radius.circular(rl.fieldRadius + 2) : Radius.zero,
                      bottom: isLast  ? Radius.circular(rl.fieldRadius + 2) : Radius.zero,
                    ),
                    // FIX(gap): select by index so coordinates travel with the tap.
                    onTap: () => _selectSuggestion(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: rl.isMobile ? 10 : 12),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                              color: _kPurpleLight, shape: BoxShape.circle),
                          child: const Icon(Icons.location_on_outlined,
                              size: 13, color: _kPurple),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_suggestions[i],
                              style: TextStyle(
                                  fontSize: rl.fieldFontSize - 0.5,
                                  color: Colors.black87),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────
  void _onLocationChanged(String value, _RL rl) {
    _location = value;
    // FIX(gap): manual edits invalidate any previously captured coordinates
    // (from a prior suggestion tap or GPS detect) — don't silently keep
    // stale lat/lng attached to new free-typed text.
    _latitude = null;
    _longitude = null;
    _debounce?.cancel();
    if (value.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500),
            () => _fetchSuggestions(value.trim(), rl));
  }

  Future<void> _fetchSuggestions(String input, _RL rl) async {
    if (!mounted) return;
    final cacheKey = input.toLowerCase();

    // FIX(perf): served straight from memory — no network round-trip at all.
    final cached = _suggestionCache[cacheKey];
    if (cached != null) {
      setState(() {
        _suggestions = cached.names;
        _suggestionCoords = cached.coords;
      });
      _showOverlay(rl);
      return;
    }

    final requestId = ++_suggestionRequestId;
    setState(() => _isFetchingSuggestions = true);
    try {
      final url = Uri.parse('$_kNominatimBase'
          '?q=${Uri.encodeComponent(input)}&format=json&limit=5&addressdetails=1');
      final response = await _httpClient.get(url, headers: {
        'User-Agent': 'SwapNow/1.0 (com.credbro.app)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 8));

      // A newer request has since superseded this one — drop the result.
      if (!mounted || requestId != _suggestionRequestId) return;

      if (response.statusCode == 200) {
        final List<dynamic> data =
        json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        final filtered = data
            .whereType<Map<String, dynamic>>()
            .where((e) => (e['display_name'] as String? ?? '').trim().isNotEmpty)
            .take(5)
            .toList();

        final names = filtered
            .map<String>((e) => (e['display_name'] as String).trim())
            .toList();
        // FIX(gap): capture each suggestion's lat/lon from Nominatim
        // alongside the display text, so selecting it doesn't require a
        // second, separately-fallible geocode later.
        final coords = filtered.map<Map<String, double>?>((e) {
          final lat = double.tryParse(e['lat']?.toString() ?? '');
          final lon = double.tryParse(e['lon']?.toString() ?? '');
          if (lat == null || lon == null) return null;
          return {'lat': lat, 'lng': lon};
        }).toList();

        if (_suggestionCache.length >= _kSuggestionCacheCap) {
          _suggestionCache.remove(_suggestionCache.keys.first);
        }
        _suggestionCache[cacheKey] = _SuggestionResult(names, coords);

        setState(() {
          _suggestions = names;
          _suggestionCoords = coords;
        });
        _showOverlay(rl);
      } else {
        setState(() {
          _suggestions = [];
          _suggestionCoords = [];
        });
        _removeOverlay();
      }
    } on TimeoutException {
      if (mounted && requestId == _suggestionRequestId) {
        setState(() { _suggestions = []; _suggestionCoords = []; });
        _removeOverlay();
      }
    } catch (_) {
      if (mounted && requestId == _suggestionRequestId) {
        setState(() { _suggestions = []; _suggestionCoords = []; });
        _removeOverlay();
      }
    } finally {
      if (mounted && requestId == _suggestionRequestId) {
        setState(() => _isFetchingSuggestions = false);
      }
    }
  }

  void _selectSuggestion(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final suggestion = _suggestions[index];
    final trimmed = suggestion.split(',').map((s) => s.trim()).take(3).join(', ');
    final coords = index < _suggestionCoords.length ? _suggestionCoords[index] : null;
    _locationController.text = trimmed;
    _location = trimmed;
    // FIX(gap): persist the coordinates that came with this suggestion.
    _latitude = coords?['lat'];
    _longitude = coords?['lng'];
    _locationFocusNode.unfocus();
    setState(() {
      _suggestions = [];
      _suggestionCoords = [];
    });
    _removeOverlay();
  }

  // ── GPS detect ────────────────────────────────────────────────────────────
  Future<void> _detectLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showErrorSnack("Location services are disabled. Turn on GPS.");
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) _showErrorSnack("Location permission denied. Enable it in Settings.");
      return;
    }
    if (!mounted) return;
    setState(() => _isDetectingLocation = true);
    _removeOverlay();
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (!mounted) return;
      if (marks.isNotEmpty) {
        final p = marks.first;
        final readable = [p.locality, p.administrativeArea, p.country]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        setState(() {
          _location = readable.isNotEmpty ? readable : 'Unknown Location';
          _locationController.text = _location;
          _suggestions = [];
          _suggestionCoords = [];
          // FIX(gap): GPS already gives exact coordinates — keep them
          // instead of discarding after using them only for reverse-geocode.
          _latitude = pos.latitude;
          _longitude = pos.longitude;
        });
      }
    } on TimeoutException {
      if (mounted) _showErrorSnack("Location timed out. Try again.");
    } catch (_) {
      if (mounted) _showErrorSnack("Failed to get address. Try again.");
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
    }
  }

  // ── Images ────────────────────────────────────────────────────────────────
  int get _totalImages => _images.length;

  Future<void> _pickImages() async {
    final remaining = _kMaxImages - _totalImages;
    if (remaining <= 0) {
      _showErrorSnack("Maximum $_kMaxImages images allowed.");
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (picked == null || picked.isEmpty) return;
      if (!mounted) return;
      final toAdd = picked.take(remaining).toList();
      setState(() => _images.addAll(toAdd));
      for (final img in toAdd) {
        // Kick off compression now and cache the Future immediately, so a
        // fast Publish tap reuses this work instead of duplicating it.
        unawaited(_precompress(img));
      }
    } catch (_) {
      if (mounted) _showErrorSnack("Failed to pick images. Try again.");
    }
  }

  Future<void> _precompress(XFile img) async {
    _compressedCache[img.path] ??= _compressImage(img);
    await _compressedCache[img.path];
  }

  void _removeImage(int index) {
    if (index < 0 || index >= _images.length) return;
    final removed = _images[index];
    _compressedCache.remove(removed.path);
    setState(() => _images.removeAt(index));
  }

  Future<Uint8List?> _compressImage(XFile img) async {
    final file = File(img.path);
    if (!await file.exists()) return null;
    try {
      return await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: _kCompressMaxDim, minHeight: _kCompressMaxDim,
          quality: _kCompressQuality, format: CompressFormat.jpeg,
          keepExif: false);
    } catch (_) { return null; }
  }

  // ── Validation ────────────────────────────────────────────────────────────
  String? _firstValidationError() {
    if (_totalImages == 0) return "Please add at least one image.";
    if (_titleController.text.trim().isEmpty) return "Please enter a product title.";
    if (_titleController.text.trim().length > 120) return "Title must be 120 characters or fewer.";
    if (_descriptionController.text.trim().length < 10) return "Description must be at least 10 characters.";
    if (_descriptionController.text.trim().length > 2000) return "Description must be 2,000 characters or fewer.";
    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) return "Please enter a price.";
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) return "Please enter a valid price greater than 0.";
    if (price > 9999999) return "Price seems too high — please double-check it.";
    if (_condition == null) return "Please select a condition.";
    if (_category  == null) return "Please select a category.";
    if (_location.trim().isEmpty) return "Please set your location.";
    // FIX(gap): a location without coordinates silently breaks distance
    // sorting/filtering on the home page — require the user to pick a
    // suggestion or use GPS detect rather than accept free-typed text.
    if (_latitude == null || _longitude == null) {
      return "Please pick your location from the suggestions list or use \"detect current location\".";
    }
    return null;
  }

  // ── Listing fee helpers ───────────────────────────────────────────────────
  double get _enteredPrice => double.tryParse(_priceController.text.trim()) ?? 0;

  // 20% of the entered price, floored at Razorpay's ₹1 minimum and capped at
  // ₹100 — a preview only; functions/index.js computes the real charge.
  double get _perListingFeePreview {
    final raw = _enteredPrice * _kPerListingFeeRate;
    if (raw < _kPerListingFeeMinRupees) return _kPerListingFeeMinRupees;
    if (raw > _kPerListingFeeCapRupees) return _kPerListingFeeCapRupees;
    return raw;
  }

  Future<bool> _hasLifetimeListingAccess(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return doc.data()?['hasLifetimeListingAccess'] == true;
    } catch (_) {
      // If the check itself fails, fall through to the fee dialog rather
      // than silently letting an unpaid publish through.
      return false;
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final error = _firstValidationError();
    if (error != null) { _showErrorSnack(error); return; }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showErrorSnack("You must be logged in to upload.");
        return;
      }

      final alreadyUnlocked = await _hasLifetimeListingAccess(user.uid);
      if (!mounted) return;

      if (alreadyUnlocked) {
        await _publishListing(user);
        return;
      }

      final chosen = await _showListingFeeDialog();
      if (chosen == null) return; // user dismissed the dialog — not an error
      if (!mounted) return;
      await _startListingCheckout(chosen, user);
      // From here on the Razorpay event handlers below take over: they push
      // PaymentSuccessPage / PaymentFailedPage, and the actual publish runs
      // from PaymentSuccessPage's Continue button, which then pops back here.
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _publishListing(User user, {_ListingFeeType? feeTypeCharged}) async {
    try {
      final imageUrls = await _uploadImagesParallel(user.uid);
      if (imageUrls == null) return;

      await FirebaseFirestore.instance.collection('UserProductList').add({
        'userId'     : user.uid,
        'title'      : _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price'      : _enteredPrice,
        'category'   : _category,
        'condition'  : _condition,
        'location'   : _location.trim(),
        // FIX(gap): persist coordinates so home_page.dart can sort/filter
        // by distance without a live, failure-prone geocode of the string.
        'lat'        : _latitude,
        'lng'        : _longitude,
        'images'     : imageUrls,
        'createdAt'  : FieldValue.serverTimestamp(),
        'status'     : 'active',
        // Record-only — how (if at all) this specific publish was paid for.
        // Doesn't drive any access logic; hasLifetimeListingAccess on the
        // user doc is what actually gates future publishes.
        if (feeTypeCharged != null)
          'listingFeeType': feeTypeCharged == _ListingFeeType.lifetime ? 'lifetime' : 'perListing',
      });

      if (!mounted) return;
      _showSuccessSnack("Product published successfully!");
      _resetForm();
    } on FirebaseException catch (e) {
      if (mounted) _showErrorSnack("Upload failed: ${e.message ?? 'Try again.'}");
    } catch (_) {
      if (mounted) _showErrorSnack("Failed to publish product. Try again.");
    }
  }

  // ── Listing fee dialog ────────────────────────────────────────────────────
  Future<_ListingFeeType?> _showListingFeeDialog() {
    return showDialog<_ListingFeeType>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ListingFeeDialog(
        perListingFeePreview: _perListingFeePreview,
      ),
    );
  }

  // ── Razorpay checkout for the listing fee ────────────────────────────────
  // Opens checkout and returns as soon as it's on screen — it does NOT wait
  // for the outcome. Success/failure arrive later via the event handlers
  // below, which is where PaymentSuccessPage/PaymentFailedPage get shown.
  Future<void> _startListingCheckout(_ListingFeeType feeType, User user) async {
    String orderId;
    int amountPaise;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('createListingOrder');
      final result = await callable.call({
        'feeType': feeType == _ListingFeeType.lifetime ? 'lifetime' : 'perListing',
        if (feeType == _ListingFeeType.perListing) 'price': _enteredPrice,
      }).timeout(const Duration(seconds: 15));
      final data = result.data as Map;
      orderId = data['orderId'] as String;
      amountPaise = data['amount'] as int;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('createListingOrder rejected: ${e.code} ${e.message}');
      if (mounted) _showErrorSnack("Could not start payment. Please try again.");
      return;
    } catch (e) {
      debugPrint('createListingOrder call error: $e');
      if (mounted) _showErrorSnack("Network error. Please check your connection and retry.");
      return;
    }

    final options = {
      'key': _razorpayKey,
      'amount': amountPaise,
      'order_id': orderId,
      'name': 'SwapNow',
      'description': feeType == _ListingFeeType.lifetime
          ? 'Lifetime listing access'
          : 'Listing fee for this product',
      'prefill': {'contact': user.phoneNumber ?? ''},
      'external': {
        'wallets': ['paytm']
      },
      'method': {'upi': true, 'card': true, 'netbanking': true, 'wallet': true},
      'theme': {'color': '#6A00FF'},
      'notes': {'uid': user.uid},
    };

    _pendingFeeType = feeType;
    _pendingAmountPaise = amountPaise;
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Razorpay open error: $e');
      _pendingFeeType = null;
      _pendingAmountPaise = null;
      if (mounted) _showErrorSnack("Could not open payment. Please try again.");
    }
  }

  void _handleListingPaymentSuccess(PaymentSuccessResponse response) async {
    final feeType = _pendingFeeType;
    final amountPaise = _pendingAmountPaise;
    _pendingFeeType = null;
    _pendingAmountPaise = null;
    if (feeType == null || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final paymentId = response.paymentId ?? 'unknown';
    final orderId = response.orderId ?? '';
    final signature = response.signature ?? '';
    final now = DateTime.now();

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyListingPayment');
      final result = await callable.call({
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
        'feeType': feeType == _ListingFeeType.lifetime ? 'lifetime' : 'perListing',
        if (amountPaise != null) 'amount': amountPaise,
      }).timeout(const Duration(seconds: 15));

      final verified = (result.data as Map)['verified'] == true;
      if (!verified) throw Exception('Server did not confirm verification.');

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            paymentId: paymentId,
            time: now.toIso8601String(),
            subtitle: feeType == _ListingFeeType.lifetime
                ? "Lifetime listing access unlocked — every future listing is free."
                : "Listing fee received for this product.",
            // Runs the actual publish (image upload + Firestore write) while
            // this page's own Continue button shows its spinner, then pops
            // back to the listing page — "back to where it started".
            onContinue: () async {
              if (user != null) {
                await _publishListing(user, feeTypeCharged: feeType);
              }
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('verifyListingPayment rejected: ${e.code} ${e.message}');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentFailedPage(
            errorCode: e.code,
            errorMessage:
            "Payment received but verification failed. Contact support with payment ID: $paymentId",
            onRetry: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('verifyListingPayment call error: $e');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentFailedPage(
            errorCode: "VERIFY_ERROR",
            errorMessage:
            "Couldn't confirm payment. Contact support with payment ID: $paymentId if this persists.",
            onRetry: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  void _handleListingPaymentError(PaymentFailureResponse response) {
    _pendingFeeType = null;
    _pendingAmountPaise = null;
    if (!mounted) return;

    final message = response.code == Razorpay.PAYMENT_CANCELLED
        ? "Payment was cancelled."
        : response.code == Razorpay.NETWORK_ERROR
        ? "Network error. Please check your connection and retry."
        : "Payment failed. Please try a different payment method.";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentFailedPage(
          errorCode: (response.code ?? 0).toString(),
          errorMessage: message,
          // Just returns the user to the listing page — they can tap
          // Publish again to retry from scratch.
          onRetry: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _handleListingExternalWallet(ExternalWalletResponse response) {
    _pendingFeeType = null;
    _pendingAmountPaise = null;
    if (mounted) _showSuccessSnack("Redirecting to ${response.walletName ?? 'wallet'}...");
  }

  Future<List<String>?> _uploadImagesParallel(String uid) async {
    if (_images.isEmpty) return [];
    try {
      final results = await Future.wait(
          _images.map((img) => _uploadSingleImage(uid, img)));
      if (results.any((url) => url == null)) {
        if (mounted) _showErrorSnack("An image failed to upload. Try again.");
        return null;
      }
      return results.cast<String>();
    } catch (_) {
      if (mounted) _showErrorSnack("Image upload failed. Try again.");
      return null;
    }
  }

  Future<String?> _uploadSingleImage(String uid, XFile img) async {
    // FIX(perf): reuses whatever compression Future is already running
    // (started at pick time) instead of starting a second one — this was
    // silently doubling compression work whenever Publish was tapped
    // quickly after picking images.
    final compressed = await (_compressedCache[img.path] ??= _compressImage(img));
    if (compressed == null) return null;
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${img.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final ref = FirebaseStorage.instance
        .ref()
        .child('UserProductList/$uid/$filename');
    await ref.putData(compressed,
        SettableMetadata(contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000'));
    return await ref.getDownloadURL();
  }

  void _resetForm() {
    _compressedCache.clear();
    setState(() {
      _images.clear();
      _titleController.clear();
      _descriptionController.clear();
      _priceController.clear();
      _category = null;
      _condition = null;
      _locationController.clear();
      _location = '';
      // FIX(gap): clear coordinates along with the rest of the form.
      _latitude = null;
      _longitude = null;
    });
  }

  // ── Snackbars ─────────────────────────────────────────────────────────────
  void _showSuccessSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: const Color(0xFF1B8A4C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ));
  }

  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final rl = _RL(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Add Swap Product",
                style: TextStyle(
                    fontSize: rl.appBarFontSize,
                    color: _kLabel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text("Fill in your listing details",
                style: TextStyle(
                    fontSize: 11.5, color: _kSubtext, fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: rl.scrollPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── 1 · Photos ───────────────────────────────────────────
                  _SectionCard(
                    stepNumber: 1,
                    icon: Icons.photo_library_outlined,
                    title: "Photos",
                    subtitle: "First image is the cover photo",
                    rl: rl,
                    child: _buildImageGrid(rl),
                  ),
                  SizedBox(height: rl.sectionGap),

                  // ── 2 · Product Details ──────────────────────────────────
                  _SectionCard(
                    stepNumber: 2,
                    icon: Icons.inventory_2_outlined,
                    title: "Product Details",
                    subtitle: "Describe what you're swapping",
                    rl: rl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(text: "Title", rl: rl),
                        _InputField(
                          rl: rl,
                          controller: _titleController,
                          hintText: "e.g. Sony WH-1000XM5 Headphones",
                          prefixIcon: Icons.label_outline_rounded,
                          maxLength: 120,
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: rl.sectionGap),
                        _FieldLabel(text: "Description", rl: rl),
                        _InputField(
                          rl: rl,
                          controller: _descriptionController,
                          maxLines: rl.isTablet || rl.isDesktop ? 4 : 3,
                          maxLength: 2000,
                          hintText: "Condition, features, reason for swapping…",
                          prefixIcon: Icons.notes_rounded,
                          alignLabelWithHint: true,
                        ),
                        SizedBox(height: rl.sectionGap),
                        _FieldLabel(text: "Price (₹)", rl: rl),
                        _InputField(
                          rl: rl,
                          controller: _priceController,
                          hintText: "e.g. 1500",
                          prefixIcon: Icons.currency_rupee_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rl.sectionGap),

                  // ── 3 · Condition ─────────────────────────────────────────
                  _SectionCard(
                    stepNumber: 3,
                    icon: Icons.sell_outlined,
                    title: "Condition",
                    subtitle: "Set item condition",
                    rl: rl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(text: "Condition", rl: rl),
                        _DropdownField(
                          rl: rl,
                          value: _condition,
                          hint: "Select",
                          items: _kConditions,
                          prefixIcon: Icons.star_outline_rounded,
                          onChanged: (v) => setState(() => _condition = v),
                          isExpanded: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rl.sectionGap),

                  // ── 4 · Category ─────────────────────────────────────────
                  _SectionCard(
                    stepNumber: 4,
                    icon: Icons.category_outlined,
                    title: "Category",
                    subtitle: "Help buyers find your listing",
                    rl: rl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(text: "Select Category", rl: rl),
                        _DropdownField(
                          rl: rl,
                          value: _category,
                          hint: "Choose a category",
                          items: _kCategories,
                          prefixIcon: Icons.grid_view_rounded,
                          onChanged: (v) => setState(() => _category = v),
                          isExpanded: true,
                        ),
                        const SizedBox(height: 12),
                        _buildCategoryChips(rl),
                      ],
                    ),
                  ),
                  SizedBox(height: rl.sectionGap),

                  // ── 5 · Location ─────────────────────────────────────────
                  _SectionCard(
                    stepNumber: 5,
                    icon: Icons.location_on_outlined,
                    title: "Location",
                    subtitle: "Nearby people find you first",
                    rl: rl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(text: "Your City / Area", rl: rl),
                        _buildLocationField(rl),
                        if (_location.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kPurpleLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              Icon(
                                // FIX(gap): visually confirm whether this
                                // location actually carries coordinates.
                                _latitude != null && _longitude != null
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                color: _latitude != null && _longitude != null
                                    ? _kPurple
                                    : Colors.orange,
                                size: 15,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(_location,
                                    style: TextStyle(
                                        fontSize: rl.fieldFontSize - 1,
                                        color: _kPurple,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: rl.sectionGap + 8),

                  // ── Publish Button ────────────────────────────────────────
                  _buildPublishButton(rl),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Category chips ────────────────────────────────────────────────────────
  static const List<String> _kPopularCats = [
    'Mobile Phones', 'Laptops', 'Clothes', 'Books', 'Electronics', 'Furniture',
  ];

  Widget _buildCategoryChips(_RL rl) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kPopularCats.map((cat) {
        final selected = _category == cat;
        return GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? _kPurple : Colors.white,
              border: Border.all(
                  color: selected ? _kPurple : _kBorder, width: 1.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(cat,
                style: TextStyle(
                    fontSize: rl.fieldFontSize - 1.5,
                    color: selected ? Colors.white : _kSubtext,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ),
        );
      }).toList(),
    );
  }

  // ── Location field ────────────────────────────────────────────────────────
  Widget _buildLocationField(_RL rl) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: _FieldShell(
        rl: rl,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: _isFetchingSuggestions
                ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))
                : const Icon(Icons.search_rounded, color: _kPurple, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: _locationController,
              focusNode: _locationFocusNode,
              keyboardType: TextInputType.streetAddress,
              textInputAction: TextInputAction.done,
              style: TextStyle(fontSize: rl.fieldFontSize, color: Colors.black87),
              onChanged: (v) => _onLocationChanged(v, rl),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: rl.fieldContentPadding,
                hintText: "Type city or area…",
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: rl.fieldFontSize),
                isDense: false,
              ),
            ),
          ),
          _isDetectingLocation
              ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kPurple)))
              : IconButton(
              tooltip: "Detect my location",
              icon: const Icon(Icons.my_location_rounded,
                  color: _kPurple, size: 20),
              splashRadius: 20,
              onPressed: _isDetectingLocation ? null : _detectLocation),
        ]),
      ),
    );
  }

  // ── Image grid ────────────────────────────────────────────────────────────
  Widget _buildImageGrid(_RL rl) {
    return Wrap(
      spacing: rl.thumbSpacing,
      runSpacing: rl.thumbSpacing,
      children: [
        ..._images.asMap().entries.map((e) => _thumbStack(
          rl: rl,
          child: Image.file(
            File(e.value.path),
            width: rl.thumbSize, height: rl.thumbSize,
            fit: BoxFit.cover,
            cacheWidth: (rl.thumbSize * 2).toInt(),
            errorBuilder: (_, __, ___) => Container(
                width: rl.thumbSize, height: rl.thumbSize,
                color: Colors.grey.shade100,
                child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
          ),
          onRemove: () => _removeImage(e.key),
          isCover: e.key == 0,
        )),
        if (_totalImages < _kMaxImages) _buildAddSlot(rl),
      ],
    );
  }

  Widget _thumbStack({
    required _RL rl,
    required Widget child,
    required VoidCallback onRemove,
    bool isCover = false,
  }) {
    return SizedBox(
      width: rl.thumbSize,
      height: rl.thumbSize,
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(rl.thumbRadius),
          child: SizedBox(
              width: rl.thumbSize, height: rl.thumbSize, child: child),
        ),
        if (isCover)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, _kPurple.withOpacity(0.85)]),
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(rl.thumbRadius)),
              ),
              alignment: Alignment.center,
              child: const Text("Cover",
                  style: TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
          ),
        Positioned(
          top: 5, right: 5,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.62), shape: BoxShape.circle),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildAddSlot(_RL rl) {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: rl.thumbSize, height: rl.thumbSize,
        decoration: BoxDecoration(
          color: _kPurple.withOpacity(0.04),
          border: Border.all(color: _kPurple.withOpacity(0.3), width: 1.5),
          borderRadius: BorderRadius.circular(rl.thumbRadius),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(color: _kPurpleLight, shape: BoxShape.circle),
            child: Icon(Icons.add_photo_alternate_outlined,
                size: (rl.thumbSize * 0.22).clamp(18.0, 30.0), color: _kPurple),
          ),
          const SizedBox(height: 6),
          Text("Add Photo",
              style: TextStyle(fontSize: 10.5, color: _kPurple, fontWeight: FontWeight.w600)),
          Text("$_totalImages/$_kMaxImages",
              style: const TextStyle(fontSize: 9.5, color: _kSubtext)),
        ]),
      ),
    );
  }

  // ── Publish button ────────────────────────────────────────────────────────
  Widget _buildPublishButton(_RL rl) {
    return GestureDetector(
      onTap: _isSubmitting ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: rl.saveButtonHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isSubmitting
                ? [Colors.grey.shade400, Colors.grey.shade500]
                : [_kPurple, _kPurpleDark],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(rl.saveButtonRadius),
          boxShadow: _isSubmitting
              ? []
              : [BoxShadow(
              color: _kPurple.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: _isSubmitting
            ? const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
            : Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_upload_outlined,
              color: Colors.white, size: 20),
          const SizedBox(width: 9),
          Text("Publish Product",
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: rl.saveButtonFontSize,
                  letterSpacing: 0.2)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  LISTING FEE — selection dialog
// ══════════════════════════════════════════════════════════════════════════════
/// Shown before Publish whenever the signed-in user doesn't already have
/// hasLifetimeListingAccess. Lets them pick between a one-time ₹49 lifetime
/// unlock, or a per-listing fee (20% of their asking price, capped ₹100).
class _ListingFeeDialog extends StatefulWidget {
  final double perListingFeePreview;
  const _ListingFeeDialog({required this.perListingFeePreview});

  @override
  State<_ListingFeeDialog> createState() => _ListingFeeDialogState();
}

class _ListingFeeDialogState extends State<_ListingFeeDialog> {
  _ListingFeeType _selected = _ListingFeeType.lifetime;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: _kPurpleLight, shape: BoxShape.circle),
                  child: const Icon(Icons.workspace_premium_outlined, color: _kPurple, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Choose how to publish",
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kLabel)),
                ),
              ]),
              const SizedBox(height: 6),
              Text("Pick a plan to publish this listing.",
                  style: TextStyle(fontSize: 13, color: _kSubtext)),
              const SizedBox(height: 18),
              _FeeOptionCard(
                selected: _selected == _ListingFeeType.lifetime,
                title: "Lifetime access",
                subtitle: "Pay once — every future listing is free.",
                priceLabel: "₹${_kLifetimeFeeRupees.toStringAsFixed(0)}",
                priceSublabel: "one-time",
                onTap: () => setState(() => _selected = _ListingFeeType.lifetime),
              ),
              const SizedBox(height: 10),
              _FeeOptionCard(
                selected: _selected == _ListingFeeType.perListing,
                title: "Pay per listing",
                subtitle: "Capped at ₹${_kPerListingFeeCapRupees.toStringAsFixed(0)}."
                    " Charged again next time.",
                priceLabel: "₹${widget.perListingFeePreview.toStringAsFixed(2)}",
                priceSublabel: "this listing",
                onTap: () => setState(() => _selected = _ListingFeeType.perListing),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        foregroundColor: _kSubtext),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeeOptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String priceLabel;
  final String priceSublabel;
  final VoidCallback onTap;

  const _FeeOptionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.priceSublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _kPurpleLight : Colors.white,
          border: Border.all(color: selected ? _kPurple : _kBorder, width: selected ? 1.6 : 1.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
            color: selected ? _kPurple : Colors.grey.shade400,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _kLabel)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 12, color: _kSubtext, height: 1.3)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(priceLabel,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: selected ? _kPurple : _kLabel)),
            Text(priceSublabel, style: TextStyle(fontSize: 10.5, color: _kSubtext)),
          ]),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTION CARD
// ══════════════════════════════════════════════════════════════════════════════
class _SectionCard extends StatelessWidget {
  final int      stepNumber;
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Widget   child;
  final _RL      rl;

  const _SectionCard({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.rl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(rl.cardRadius),
        border: Border.all(color: _kBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF6A00FF).withOpacity(0.05),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: EdgeInsets.fromLTRB(rl.cardPad, rl.cardPad, rl.cardPad, 12),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kPurple, _kPurpleDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('$stepNumber',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontSize: rl.labelFontSize + 1,
                        fontWeight: FontWeight.w700,
                        color: _kLabel,
                        letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: rl.labelFontSize - 1.5,
                        color: _kSubtext,
                        fontWeight: FontWeight.w400)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: _kPurpleLight, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: _kPurple, size: 18),
            ),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: _kBorder),
        Padding(padding: EdgeInsets.all(rl.cardPad), child: child),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FIELD LABEL
// ══════════════════════════════════════════════════════════════════════════════
class _FieldLabel extends StatelessWidget {
  final String text;
  final _RL    rl;
  const _FieldLabel({required this.text, required this.rl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: rl.labelFontSize,
              color: _kLabel,
              letterSpacing: -0.1)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  INPUT FIELD
// ══════════════════════════════════════════════════════════════════════════════
class _InputField extends StatelessWidget {
  final _RL                       rl;
  final TextEditingController     controller;
  final int                       maxLines;
  final int?                      maxLength;
  final TextInputType             keyboardType;
  final TextInputAction           textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final String?                   hintText;
  final IconData?                 prefixIcon;
  final bool                      alignLabelWithHint;

  const _InputField({
    required this.rl,
    required this.controller,
    this.maxLines           = 1,
    this.maxLength,
    this.keyboardType       = TextInputType.text,
    this.textInputAction    = TextInputAction.next,
    this.inputFormatters,
    this.hintText,
    this.prefixIcon,
    this.alignLabelWithHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      rl: rl,
      child: Row(
        crossAxisAlignment: alignLabelWithHint && maxLines > 1
            ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (prefixIcon != null) ...[
            Padding(
              padding: EdgeInsets.only(
                  left: 12, right: 8,
                  top: alignLabelWithHint && maxLines > 1
                      ? rl.fieldContentPadding.vertical / 2 : 0),
              child: Icon(prefixIcon,
                  color: _kPurple.withOpacity(0.65), size: 17),
            ),
          ],
          Expanded(
            child: TextFormField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
              style: TextStyle(fontSize: rl.fieldFontSize, color: Colors.black87),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: rl.fieldFontSize),
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.symmetric(
                    horizontal: prefixIcon != null ? 0 : 12,
                    vertical: rl.fieldContentPadding.vertical / 2),
                isDense: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DROPDOWN FIELD
// ══════════════════════════════════════════════════════════════════════════════
class _DropdownField extends StatelessWidget {
  final _RL                   rl;
  final String?               value;
  final String                hint;
  final List<String>          items;
  final ValueChanged<String?> onChanged;
  final IconData?             prefixIcon;
  final bool                  isExpanded;

  const _DropdownField({
    required this.rl,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.prefixIcon,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      rl: rl,
      child: Row(children: [
        if (prefixIcon != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Icon(prefixIcon, color: _kPurple.withOpacity(0.65), size: 17),
          ),
        ],
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: isExpanded,
              hint: Text(hint,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: rl.fieldFontSize)),
              style: TextStyle(fontSize: rl.fieldFontSize, color: Colors.black87),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(rl.fieldRadius + 2),
              items: items.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  FIELD SHELL
// ══════════════════════════════════════════════════════════════════════════════
class _FieldShell extends StatelessWidget {
  final _RL    rl;
  final Widget child;
  const _FieldShell({required this.rl, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kBorder, width: 1.3),
        borderRadius: BorderRadius.circular(rl.fieldRadius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.025),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}