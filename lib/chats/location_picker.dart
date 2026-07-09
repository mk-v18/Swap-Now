import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  LatLng? _picked;
  LatLng _center = const LatLng(17.385, 78.4867);
  bool _locating = true;
  bool _sending = false;
  bool _searching = false;
  String? _locationError; // non-null => show retry chip instead of silently failing

  static const Color _purple = Color(0xFF7B1FA2);
  static const Duration _locationTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _goToMyLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.info_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
        backgroundColor: error ? const Color(0xFFB00020) : Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: action != null ? 5 : 3),
        action: action,
      ));
  }

  Future<void> _goToMyLocation() async {
    if (!mounted) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationError = 'Location services are turned off';
        });
        _snack(
          'Turn on location services to use your current position',
          error: true,
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => Geolocator.openLocationSettings(),
          ),
        );
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationError = 'Location permission permanently denied';
        });
        _snack(
          'Location permission is disabled. Enable it in app settings.',
          error: true,
          action: SnackBarAction(
            label: 'SETTINGS',
            textColor: Colors.white,
            onPressed: () => Geolocator.openAppSettings(),
          ),
        );
        return;
      }

      if (perm == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _locationError = 'Location permission denied';
        });
        _snack('You can still tap the map to place a pin manually.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        _locationTimeout,
        onTimeout: () => throw TimeoutException('Location fetch timed out'),
      );

      if (!mounted) return;
      final myLoc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = myLoc;
        _picked = myLoc;
        _locating = false;
        _locationError = null;
      });
      _mapController.move(myLoc, 15);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = 'Could not get your location';
      });
      _snack('Could not get your location — tap the map to place a pin manually', error: true);
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;

    setState(() => _searching = true);
    _searchFocus.unfocus();

    try {
      final results = await locationFromAddress(query).timeout(_locationTimeout);
      if (!mounted) return;

      if (results.isEmpty) {
        _snack('No results found for "$query"', error: true);
        return;
      }

      final match = LatLng(results.first.latitude, results.first.longitude);
      setState(() {
        _center = match;
        _picked = match;
      });
      _mapController.move(match, 16);
    } catch (_) {
      if (!mounted) return;
      _snack('Search failed — check your connection and try again', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendLocation() async {
    if (_picked == null || _sending) return;
    setState(() => _sending = true);

    String address = '';
    try {
      final placemarks = await placemarkFromCoordinates(
        _picked!.latitude,
        _picked!.longitude,
      ).timeout(_locationTimeout);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if ((p.name ?? '').isNotEmpty && p.name != p.street) p.name!,
          if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
          if ((p.locality ?? '').isNotEmpty) p.locality!,
        ];
        address = parts.isNotEmpty ? parts.join(', ') : '';
      }
    } catch (_) {
      address = ''; // non-fatal — receiver's UI already falls back to reverse-geocoding
    }

    if (!mounted) return;

    Navigator.pop(context, {
      'lat': _picked!.latitude,
      'lng': _picked!.longitude,
      'address': address,
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final isTablet = screenW >= 600;
    final bottomPadding = mq.padding.bottom;

    final markerIconSize = isTablet ? 52.0 : 40.0;
    final markerWidth = isTablet ? 60.0 : 48.0;
    final markerHeight = isTablet ? 68.0 : 56.0;
    final fabBottom = bottomPadding + (isTablet ? 32.0 : 24.0);
    final fabRight = isTablet ? 24.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _purple,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Pick Location',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 20 : 18,
          ),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _picked != null
                ? Padding(
              key: const ValueKey('send_btn'),
              padding: EdgeInsets.only(right: isTablet ? 16 : 8),
              child: _sending
                  ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              )
                  : TextButton.icon(
                onPressed: _sendLocation,
                icon: Icon(Icons.send_rounded,
                    color: Colors.white, size: isTablet ? 20 : 18),
                label: Text(
                  'Send',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 16 : 14,
                  ),
                ),
              ),
            )
                : const SizedBox.shrink(key: ValueKey('no_btn')),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15,
                onTap: (_, point) => setState(() => _picked = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.credbro.app',
                  maxNativeZoom: 19,
                ),
                if (_picked != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked!,
                        width: markerWidth,
                        height: markerHeight,
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('${_picked!.latitude},${_picked!.longitude}'),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) => Transform.scale(
                            scale: value,
                            alignment: Alignment.bottomCenter,
                            child: child,
                          ),
                          child: Icon(
                            Icons.location_on_rounded,
                            color: _purple,
                            size: markerIconSize,
                            shadows: const [
                              Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                // Required by OpenStreetMap's tile usage policy.
                RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(26),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchAddress(),
                  decoration: InputDecoration(
                    hintText: 'Search for a place or address',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: isTablet ? 15 : 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    prefixIcon: const Icon(Icons.search, color: _purple),
                    suffixIcon: _searching
                        ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
                      ),
                    )
                        : (_searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                        : null),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),

          // ── Instruction chip / location error chip ──────────────────────────
          Positioned(
            top: 68 + mq.padding.top,
            left: screenW * 0.1,
            right: screenW * 0.1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _locationError != null ? Icons.warning_amber_rounded : Icons.touch_app_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _locationError ?? 'Tap anywhere to place pin',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── My-location FAB ───────────────────────────────────────────────
          Positioned(
            bottom: fabBottom,
            right: fabRight,
            child: FloatingActionButton(
              heroTag: 'myLoc',
              backgroundColor: Colors.white,
              elevation: 4,
              mini: !isTablet,
              onPressed: _locating ? null : _goToMyLocation,
              child: _locating
                  ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
              )
                  : const Icon(Icons.my_location_rounded, color: _purple),
            ),
          ),
        ],
      ),
    );
  }
}