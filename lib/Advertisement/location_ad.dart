import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class LocationAdWidget extends StatefulWidget {
  /// Pass a label like 'Large Banner (320×100)' to filter by size.
  /// Defaults to 'Large Banner (320×100)' when null.
  final String? targetAdSize;

  const LocationAdWidget({super.key, this.targetAdSize});

  @override
  State<LocationAdWidget> createState() => _LocationAdWidgetState();
}

class _LocationAdWidgetState extends State<LocationAdWidget> {
  // ── State ──────────────────────────────────────────────────────────────────
  String? _adImageUrl;
  Map<String, dynamic>? _currentAd;
  bool _loading = true;

  BannerAd? _adMobBanner;
  bool _adMobLoaded = false;

  // ── Ad size reference table ────────────────────────────────────────────────
  // Keys must match the 'adSize' values written by AdvertisementPage exactly.
  static const Map<String, Size> _logicalSizes = {
    'Banner (320×50)':            Size(320,  50),
    'Large Banner (320×100)':     Size(320, 100),
    'Medium Rectangle (300×250)': Size(300, 250),
  };

  static const double _radiusKm = 30.0;

  String get _effectiveLabel =>
      widget.targetAdSize ?? 'Large Banner (320×100)';

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadNearbyAd();
  }

  @override
  void dispose() {
    _adMobBanner?.dispose();
    super.dispose();
  }

  // ── Load nearby ad from Firestore ──────────────────────────────────────────
  Future<void> _loadNearbyAd() async {
    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        _fallbackToAdMob();
        return;
      }

      final snapshot =
      await FirebaseFirestore.instance.collection('ads').get();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // ── Field names match what AdvertisementPage writes ────────────────
        final adLat   = (data['latitude']  as num?)?.toDouble();
        final adLon   = (data['longitude'] as num?)?.toDouble();
        final adSize  = (data['adSize']    as String?) ?? 'Large Banner (320×100)';
        final imageUrl = data['image']     as String?;   // key is 'image'

        // Skip if caller requested a specific size and this doc doesn't match
        if (widget.targetAdSize != null && adSize != widget.targetAdSize) {
          continue;
        }

        // ── Skip expired ads ───────────────────────────────────────────────
        final expiresAt = data['expiresAt'] as Timestamp?;
        final isExpired = expiresAt != null &&
            expiresAt.toDate().isBefore(DateTime.now());
        if (isExpired) continue;

        if (adLat != null && adLon != null && imageUrl != null) {
          final distKm = _haversineKm(
            position.latitude, position.longitude,
            adLat, adLon,
          );

          if (distKm <= _radiusKm) {
            if (mounted) {
              setState(() {
                _adImageUrl = imageUrl;
                _currentAd  = data;
                _loading    = false;
              });
            }
            return; // First matching ad wins
          }
        }
      }

      // No nearby ad found → fall back to AdMob
      _fallbackToAdMob();
    } catch (e) {
      debugPrint('LocationAdWidget error: $e');
      _fallbackToAdMob();
    }
  }

  // ── AdMob fallback ─────────────────────────────────────────────────────────
  void _fallbackToAdMob() {
    if (!mounted) return;
    setState(() => _loading = false);

    _adMobBanner = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // test unit
      size:     _toAdMobSize(_effectiveLabel),
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _adMobLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob failed: $error');
          ad.dispose();
        },
      ),
    )..load();
  }

  // ── GPS ────────────────────────────────────────────────────────────────────
  Future<Position?> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return null;

    return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  // ── Haversine distance ─────────────────────────────────────────────────────
  double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const R    = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a    = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Size helpers ───────────────────────────────────────────────────────────
  AdSize _toAdMobSize(String label) {
    switch (label) {
      case 'Large Banner (320×100)':
        return AdSize.largeBanner;
      case 'Medium Rectangle (300×250)':
        return AdSize.mediumRectangle;
      default:
        return AdSize.banner;
    }
  }

  /// Scales [logical] down proportionally so it never exceeds [maxWidth].
  Size _responsiveSize(Size logical, double maxWidth) {
    if (logical.width <= maxWidth) return logical;
    final scale = maxWidth / logical.width;
    return Size(maxWidth, logical.height * scale);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final adSizeLabel = (_currentAd?['adSize'] as String?) ?? _effectiveLabel;
    final logicalSize =
        _logicalSizes[adSizeLabel] ?? const Size(320, 100);

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth - 16
          : MediaQuery.of(context).size.width - 16;

      final displaySize = _responsiveSize(logicalSize, maxWidth);

      Widget child;

      if (_loading) {
        // ── Loading state ──────────────────────────────────────────────────
        child = SizedBox(
          width:  displaySize.width,
          height: displaySize.height,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF6A00FF), strokeWidth: 2,
            ),
          ),
        );
      } else if (_adImageUrl != null) {
        // ── Nearby custom ad ───────────────────────────────────────────────
        child = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            _adImageUrl!,
            width:  displaySize.width,
            height: displaySize.height,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : SizedBox(
              width:  displaySize.width,
              height: displaySize.height,
              child: const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF6A00FF), strokeWidth: 2),
              ),
            ),
            errorBuilder: (_, __, ___) => _placeholder(displaySize),
          ),
        );
      } else if (_adMobLoaded && _adMobBanner != null) {
        // ── AdMob fallback ─────────────────────────────────────────────────
        // AdMob banners have fixed physical sizes; FittedBox scales them down
        // on very narrow screens.
        child = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width:  logicalSize.width,
            height: logicalSize.height,
            child: AdWidget(ad: _adMobBanner!),
          ),
        );
      } else {
        // ── No ad available ────────────────────────────────────────────────
        child = _placeholder(displaySize);
      }

      return Center(child: child);
    });
  }

  Widget _placeholder(Size size) => Container(
    width:  size.width,
    height: size.height,
    decoration: BoxDecoration(
      color:        Colors.grey.shade200,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Center(
      child: Text(
        'No Ad Available',
        style: TextStyle(color: Colors.black38, fontSize: 12),
      ),
    ),
  );
}