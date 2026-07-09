import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class AdvertisementPage extends StatefulWidget {
  const AdvertisementPage({super.key});

  @override
  State<AdvertisementPage> createState() => _AdvertisementPageState();
}

class _AdvertisementPageState extends State<AdvertisementPage> {
  File?   _selectedImage;
  String? _selectedAdSize;
  String  _selectedDuration = '7 days';   // ← validity selection
  double? _latitude;
  double? _longitude;
  bool    _isUploading         = false;
  bool    _isDetectingLocation = false;
  double  _uploadProgress      = 0.0;

  final TextEditingController _locationController = TextEditingController();
  final FocusNode  _locationFocusNode = FocusNode();
  final LayerLink  _layerLink         = LayerLink();
  OverlayEntry?    _overlayEntry;

  List<String> _suggestions           = [];
  Timer?       _debounce;
  bool         _isFetchingSuggestions = false;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _purple     = Color(0xFF5800B3);
  static const _deepPurple = Color(0xFF26004D);
  static const _green      = Color(0xFF1B8A4C);
  static const _red        = Color(0xFFB00020);
  static const _amber      = Color(0xFFB07C00);

  // ── Ad size options ────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> adSizeOptions = [
    {'label': 'Banner (320×50)',             'height': 50.0,  'width': 320.0},
    {'label': 'Large Banner (320×100)',      'height': 100.0, 'width': 320.0},
    {'label': 'Medium Rectangle (300×250)', 'height': 250.0, 'width': 300.0},
  ];

  // ── Validity/duration options (label → days) ───────────────────────────────
  static const Map<String, int> _durationDays = {
    '1 day':   1,
    '3 days':  3,
    '7 days':  7,
    '14 days': 14,
    '30 days': 30,
  };

  // ── Responsive clamp ───────────────────────────────────────────────────────
  double _clamp(double v, double mn, double mx) =>
      v < mn ? mn : (v > mx ? mx : v);

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
    _removeOverlay();
    _locationFocusNode.dispose();
    _locationController.dispose();
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
    final screenWidth = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: screenWidth - 40,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
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
                  onTap: () => _selectSuggestion(_suggestions[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: _purple),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_suggestions[i],
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
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
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  // ── Nominatim autocomplete ─────────────────────────────────────────────────
  void _onLocationChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value.trim());
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isFetchingSuggestions = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(input)}&format=json&limit=5&addressdetails=1',
      );
      final response = await http.get(url,
          headers: {'User-Agent': 'SwapNow/1.0 (com.credbro.app)'});
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _suggestions =
              data.map<String>((e) => e['display_name'] as String).toList();
        });
        _showOverlay();
      } else {
        setState(() => _suggestions = []);
        _removeOverlay();
      }
    } catch (_) {
      setState(() => _suggestions = []);
      _removeOverlay();
    } finally {
      setState(() => _isFetchingSuggestions = false);
    }
  }

  void _selectSuggestion(String suggestion) {
    final parts = suggestion.split(',').map((s) => s.trim()).toList();
    _locationController.text = parts.take(3).join(', ');
    _latitude  = null;
    _longitude = null;
    _locationFocusNode.unfocus();
    setState(() => _suggestions = []);
    _removeOverlay();
  }

  // ── GPS ────────────────────────────────────────────────────────────────────
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Location services are disabled.', error: true);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission is required.', error: true);
        return;
      }
    }
    setState(() => _isDetectingLocation = true);
    _removeOverlay();
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _latitude  = position.latitude;
      _longitude = position.longitude;
      final placemarks =
      await placemarkFromCoordinates(_latitude!, _longitude!);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() {
          _locationController.text =
          '${p.locality}, ${p.administrativeArea}, ${p.country}';
          _suggestions = [];
        });
      }
    } catch (_) {
      _showSnack('Unable to fetch location', error: true);
    } finally {
      setState(() => _isDetectingLocation = false);
    }
  }

  // ── Image ──────────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final picked =
      await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final compressed = await _compressImage(File(picked.path));
        setState(() => _selectedImage = compressed ?? File(picked.path));
      }
    } catch (_) {
      _showSnack('Failed to pick image', error: true);
    }
  }

  Future<File?> _compressImage(File file) async {
    try {
      final dir        = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path, targetPath,
        minWidth: 800, minHeight: 800,
        quality: 75, format: CompressFormat.jpeg,
      );
      return result != null ? File(result.path) : null;
    } catch (_) {
      return null;
    }
  }

  // ── Publish ────────────────────────────────────────────────────────────────
  Future<void> _publishAd() async {
    if (_selectedImage == null ||
        _selectedAdSize == null ||
        _locationController.text.isEmpty) {
      _showSnack('Please fill all fields', error: true);
      return;
    }
    setState(() {
      _isUploading    = true;
      _uploadProgress = 0.0;
    });
    try {
      final fileName  = DateTime.now().millisecondsSinceEpoch.toString();
      final imagePath = 'ads/$fileName.jpg';
      final ref = FirebaseStorage.instance.ref().child(imagePath);
      final uploadTask = ref.putFile(
        _selectedImage!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      uploadTask.snapshotEvents.listen((snap) {
        if (mounted) {
          setState(() =>
          _uploadProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });
      await uploadTask;
      final imageUrl = await ref.getDownloadURL();

      // ── Compute expiry timestamp ─────────────────────────────────────────
      final days      = _durationDays[_selectedDuration] ?? 7;
      final now       = DateTime.now();
      final expiresAt = Timestamp.fromDate(now.add(Duration(days: days)));

      await FirebaseFirestore.instance.collection('ads').add({
        'image':     imageUrl,
        'imagePath': imagePath,           // ← stored for clean Storage deletion
        'adSize':    _selectedAdSize,
        'location':  _locationController.text,
        'latitude':  _latitude,
        'longitude': _longitude,
        'duration':  _selectedDuration,   // human-readable label
        'expiresAt': expiresAt,           // Firestore Timestamp — used for TTL
        'createdAt': FieldValue.serverTimestamp(),
        // NOTE: Enable Firestore TTL on the 'expiresAt' field in the
        // Firebase Console → Firestore → Indexes → TTL policies
        // so documents are auto-deleted once the ad expires.
      });

      _showSnack('Ad published for $_selectedDuration!');
      setState(() {
        _selectedImage    = null;
        _selectedAdSize   = null;
        _selectedDuration = '7 days';
        _locationController.clear();
        _latitude         = null;
        _longitude        = null;
        _uploadProgress   = 0.0;
      });
    } catch (_) {
      _showSnack('Failed to publish ad', error: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _confirmDeleteAd(QueryDocumentSnapshot doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this ad?'),
        content: const Text(
            'This will permanently remove the ad and its image. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteAd(doc);
  }

  Future<void> _deleteAd(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final imagePath = data['imagePath'] as String?;
      if (imagePath != null) {
        try {
          await FirebaseStorage.instance.ref().child(imagePath).delete();
        } catch (_) {
          // Image may already be gone — safe to ignore.
        }
      }
      await FirebaseFirestore.instance.collection('ads').doc(doc.id).delete();
      _showSnack('Ad deleted');
    } catch (_) {
      _showSnack('Failed to delete ad', error: true);
    }
  }

  // ── Edit ───────────────────────────────────────────────────────────────────
  Future<void> _openEditSheet(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditAdSheet(
        doc: doc,
        initialAdSize: data['adSize'] as String?,
        initialLocation: data['location'] as String? ?? '',
        initialDuration: data['duration'] as String? ?? '7 days',
        adSizeOptions: adSizeOptions,
        durationDays: _durationDays,
        onSave: _saveEditedAd,
      ),
    );
  }

  Future<void> _saveEditedAd({
    required QueryDocumentSnapshot doc,
    required String adSize,
    required String location,
    required String duration,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final days = _durationDays[duration] ?? 7;
      final expiresAt =
      Timestamp.fromDate(DateTime.now().add(Duration(days: days)));

      final updateData = <String, dynamic>{
        'adSize': adSize,
        'location': location,
        'duration': duration,
        'expiresAt': expiresAt,
      };
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;

      await FirebaseFirestore.instance.collection('ads').doc(doc.id).update(updateData);
      _showSnack('Ad updated');
    } catch (_) {
      _showSnack('Failed to update ad', error: true);
    }
  }

  // ── Snack ──────────────────────────────────────────────────────────────────
  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
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
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: error ? 3 : 2),
      ));
  }

  // ── Expiry formatting ──────────────────────────────────────────────────────
  String _formatExpiry(Timestamp? expiresAt) {
    if (expiresAt == null) return 'No expiry set';
    final remaining = expiresAt.toDate().difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inDays >= 1) {
      return 'Expires in ${remaining.inDays} day${remaining.inDays == 1 ? '' : 's'}';
    }
    if (remaining.inHours >= 1) {
      return 'Expires in ${remaining.inHours} hr${remaining.inHours == 1 ? '' : 's'}';
    }
    return 'Expires in ${remaining.inMinutes} min';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final mq      = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;

    final hPad       = _clamp(screenW * 0.05, 16.0, 28.0);
    final labelFontSz = _clamp(screenW * 0.038, 13.0, 16.0);
    final fieldH     = _clamp(screenH * 0.065, 50.0, 62.0);
    final btnH       = _clamp(screenH * 0.07,  52.0, 62.0);
    final btnFontSz  = _clamp(screenW * 0.044, 14.0, 17.0);
    final cardRadius = _clamp(screenW * 0.04,  12.0, 18.0);

    // Ad preview scaling
    final selectedOption = adSizeOptions.firstWhere(
          (e) => e['label'] == _selectedAdSize,
      orElse: () => adSizeOptions.first,
    );
    final rawW  = selectedOption['width']  as double;
    final rawH  = selectedOption['height'] as double;
    final scale = ((screenW - hPad * 2) / rawW).clamp(0.5, 1.5);
    final prevW = rawW * scale;
    final prevH = (rawH * scale).clamp(44.0, screenH * 0.35);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),

              // ── Ad Size ──────────────────────────────────────────────────
              _sectionCard(
                cardRadius: cardRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Ad Size', labelFontSz),
                    const SizedBox(height: 8),
                    _adSizeDropdown(fieldH, cardRadius),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Ad Validity ──────────────────────────────────────────────
              _sectionCard(
                cardRadius: cardRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Ad Validity', labelFontSz),
                    const SizedBox(height: 4),
                    Text(
                      'Ad will be automatically removed after this period.',
                      style: TextStyle(
                        fontSize: _clamp(screenW * 0.03, 10.5, 12.5),
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _durationSelector(screenW),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Image Preview ────────────────────────────────────────────
              _sectionCard(
                cardRadius: cardRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Ad Preview', labelFontSz),
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: prevW,
                          height: prevH,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(cardRadius),
                            border: Border.all(
                              color: _selectedImage != null
                                  ? _purple.withOpacity(0.5)
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: _selectedImage != null
                              ? ClipRRect(
                            borderRadius:
                            BorderRadius.circular(cardRadius),
                            child: Image.file(_selectedImage!,
                                fit: BoxFit.cover),
                          )
                              : Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: _clamp(
                                          screenW * 0.1, 24.0, 48.0),
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tap to add image',
                                      style: TextStyle(
                                        fontSize: _clamp(
                                            screenW * 0.032, 11.0, 13.0),
                                        color: Colors.grey.shade500,
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: fieldH * 0.88,
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: Icon(Icons.image_outlined,
                            color: _purple,
                            size: _clamp(screenW * 0.05, 16.0, 22.0)),
                        label: Text(
                          _selectedImage != null
                              ? 'Change Image'
                              : 'Select Image',
                          style: TextStyle(
                            color: _purple,
                            fontWeight: FontWeight.w600,
                            fontSize: _clamp(screenW * 0.038, 13.0, 15.0),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _purple.withOpacity(0.6), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(cardRadius)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Location ─────────────────────────────────────────────────
              _sectionCard(
                cardRadius: cardRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Target Location', labelFontSz),
                    const SizedBox(height: 8),
                    _locationField(fieldH, cardRadius),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ── Upload progress ──────────────────────────────────────────
              if (_isUploading) ...[
                Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _uploadProgress,
                        minHeight: 7,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                        const AlwaysStoppedAnimation<Color>(_purple),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: _clamp(screenW * 0.032, 11.0, 13.0),
                        color: _purple,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
                const SizedBox(height: 10),
              ],

              // ── Publish button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: btnH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _isUploading
                        ? LinearGradient(colors: [
                      _purple.withOpacity(0.5),
                      _deepPurple.withOpacity(0.5)
                    ])
                        : const LinearGradient(
                        colors: [_purple, _deepPurple]),
                    borderRadius: BorderRadius.circular(cardRadius),
                    boxShadow: _isUploading
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
                    onPressed: _isUploading ? null : _publishAd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(cardRadius)),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 1.8),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.rocket_launch_outlined,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Publish Ad',
                          style: TextStyle(
                            fontSize: btnFontSz,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Posted Ads section ───────────────────────────────────────
              Row(
                children: [
                  _label('Posted Ads', labelFontSz + 1),
                ],
              ),
              const SizedBox(height: 12),
              _buildPostedAdsList(cardRadius, screenW),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Posted ads list ────────────────────────────────────────────────────────
  Widget _buildPostedAdsList(double cardRadius, double screenW) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _emptyState('Failed to load ads', Icons.error_outline, _red);
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: _purple),
              ),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _emptyState(
              'No ads posted yet', Icons.campaign_outlined, Colors.grey);
        }
        return Column(
          children: docs
              .map((doc) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _adCard(doc, cardRadius, screenW),
          ))
              .toList(),
        );
      },
    );
  }

  Widget _emptyState(String message, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withOpacity(0.6), size: 28),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _adCard(QueryDocumentSnapshot doc, double cardRadius, double screenW) {
    final data       = doc.data() as Map<String, dynamic>;
    final imageUrl   = data['image'] as String?;
    final adSize     = data['adSize'] as String? ?? '—';
    final location   = data['location'] as String? ?? '—';
    final expiresAt  = data['expiresAt'] as Timestamp?;
    final expiryText = _formatExpiry(expiresAt);
    final isExpired  = expiryText == 'Expired';

    return _sectionCard(
      cardRadius: cardRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image ────────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: imageUrl != null
                      ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _purple),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade100,
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.grey.shade400, size: 24),
                    ),
                  )
                      : Container(
                    color: Colors.grey.shade100,
                    child: Icon(Icons.image_outlined,
                        color: Colors.grey.shade400, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // ── Details ──────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(adSize,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(location,
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // ── Expiry pill ──────────────────────────────────
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isExpired ? _red : _amber).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isExpired
                                ? Icons.timer_off_outlined
                                : Icons.timer_outlined,
                            size: 12,
                            color: isExpired ? _red : _amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            expiryText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isExpired ? _red : _amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),

          // ── Actions ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  color: _purple,
                  onTap: () => _openEditSheet(doc),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  color: _red,
                  onTap: () => _confirmDeleteAd(doc),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// ── Reusable labeled action button ──────────────────────────────────────
  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Duration selector (pill chips) ────────────────────────────────────────
  Widget _durationSelector(double sw) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _durationDays.keys.map((label) {
        final isSelected = _selectedDuration == label;
        return GestureDetector(
          onTap: () => setState(() => _selectedDuration = label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? _purple : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? _purple : const Color(0xFFDDD8FF),
                width: 1.5,
              ),
              boxShadow: isSelected
                  ? [
                BoxShadow(
                  color: _purple.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
                  : [],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: _clamp(sw * 0.033, 11.5, 13.5),
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black54,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'Advertisement',
        style: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
      ),
    );
  }

  // ── Section card ───────────────────────────────────────────────────────────
  Widget _sectionCard({required Widget child, required double cardRadius}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }

  // ── Label ──────────────────────────────────────────────────────────────────
  Widget _label(String text, double fontSize) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: Colors.black87,
      ),
    );
  }

  // ── Ad size dropdown ───────────────────────────────────────────────────────
  Widget _adSizeDropdown(double fieldH, double radius) {
    return Container(
      height: fieldH,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDD8FF), width: 1),
        borderRadius: BorderRadius.circular(radius),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedAdSize,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Choose ad size',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ),
          isExpanded: true,
          borderRadius: BorderRadius.circular(radius),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          items: adSizeOptions
              .map((opt) => DropdownMenuItem<String>(
            value: opt['label'],
            child: Text(opt['label'],
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
          ))
              .toList(),
          onChanged: (v) => setState(() => _selectedAdSize = v),
        ),
      ),
    );
  }

  // ── Location field ─────────────────────────────────────────────────────────
  Widget _locationField(double fieldH, double radius) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _locationController,
        focusNode: _locationFocusNode,
        keyboardType: TextInputType.streetAddress,
        onChanged: _onLocationChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: 'Type city or detect location',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide:
            const BorderSide(color: Color(0xFFDDD8FF), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide:
            const BorderSide(color: Color(0xFFDDD8FF), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(color: _purple, width: 1.5),
          ),
          prefixIcon: _isFetchingSuggestions
              ? Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _purple),
            ),
          )
              : const Icon(Icons.location_on_outlined,
              color: _purple, size: 20),
          suffixIcon: _isDetectingLocation
              ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _purple),
            ),
          )
              : IconButton(
            tooltip: 'Use current location',
            icon: const Icon(Icons.my_location,
                color: _purple, size: 20),
            onPressed: _getCurrentLocation,
          ),
        ),
      ),
    );
  }
}



class _EditAdSheet extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final String? initialAdSize;
  final String initialLocation;
  final String initialDuration;
  final List<Map<String, dynamic>> adSizeOptions;
  final Map<String, int> durationDays;
  final Future<void> Function({
  required QueryDocumentSnapshot doc,
  required String adSize,
  required String location,
  required String duration,
  double? latitude,
  double? longitude,
  }) onSave;

  const _EditAdSheet({
    required this.doc,
    required this.initialAdSize,
    required this.initialLocation,
    required this.initialDuration,
    required this.adSizeOptions,
    required this.durationDays,
    required this.onSave,
  });

  @override
  State<_EditAdSheet> createState() => _EditAdSheetState();
}

class _EditAdSheetState extends State<_EditAdSheet> {
  static const _purple = Color(0xFF5800B3);
  static const _red = Color(0xFFB00020);
  static const _green = Color(0xFF1B8A4C);

  String? _adSize;
  late String _duration;
  late TextEditingController _locationController;
  final FocusNode _locationFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  List<String> _suggestions = [];
  bool _isFetchingSuggestions = false;
  bool _isDetectingLocation = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _adSize = widget.initialAdSize;
    _duration = widget.initialDuration;
    _locationController = TextEditingController(text: widget.initialLocation);
    _locationFocusNode.addListener(() {
      if (!_locationFocusNode.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _locationFocusNode.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;
    final screenWidth = MediaQuery.of(context).size.width;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: screenWidth - 40,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final isFirst = i == 0;
                final isLast = i == _suggestions.length - 1;
                return InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: isFirst ? const Radius.circular(12) : Radius.zero,
                    bottom: isLast ? const Radius.circular(12) : Radius.zero,
                  ),
                  onTap: () => _selectSuggestion(_suggestions[i]),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: _purple),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_suggestions[i],
                              style: const TextStyle(fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
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
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _onLocationChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value.trim());
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isFetchingSuggestions = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(input)}&format=json&limit=5&addressdetails=1',
      );
      final response = await http
          .get(url, headers: {'User-Agent': 'SwapNow/1.0 (com.credbro.app)'});
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _suggestions =
              data.map<String>((e) => e['display_name'] as String).toList();
        });
        _showOverlay();
      } else {
        setState(() => _suggestions = []);
        _removeOverlay();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = []);
      _removeOverlay();
    } finally {
      if (mounted) setState(() => _isFetchingSuggestions = false);
    }
  }

  void _selectSuggestion(String suggestion) {
    final parts = suggestion.split(',').map((s) => s.trim()).toList();
    _locationController.text = parts.take(3).join(', ');
    _latitude = null;
    _longitude = null;
    _locationFocusNode.unfocus();
    setState(() => _suggestions = []);
    _removeOverlay();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Location services are disabled.', error: true);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission is required.', error: true);
        return;
      }
    }
    setState(() => _isDetectingLocation = true);
    _removeOverlay();
    try {
      final position =
      await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _latitude = position.latitude;
      _longitude = position.longitude;
      final placemarks =
      await placemarkFromCoordinates(_latitude!, _longitude!);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() {
          _locationController.text =
          '${p.locality}, ${p.administrativeArea}, ${p.country}';
          _suggestions = [];
        });
      }
    } catch (_) {
      _showSnack('Unable to fetch location', error: true);
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: error ? 3 : 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Text('Edit Ad',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),

            const Text('Ad Size',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            Container(
              height: 52,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDDD8FF)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _adSize,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  items: widget.adSizeOptions
                      .map((opt) => DropdownMenuItem<String>(
                    value: opt['label'],
                    child: Text(opt['label'],
                        style: const TextStyle(fontSize: 14)),
                  ))
                      .toList(),
                  onChanged: (v) => setState(() => _adSize = v),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text('Target Location',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87)),
            const SizedBox(height: 8),
            CompositedTransformTarget(
              link: _layerLink,
              child: TextField(
                controller: _locationController,
                focusNode: _locationFocusNode,
                keyboardType: TextInputType.streetAddress,
                onChanged: _onLocationChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Type city or detect location',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFDDD8FF), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFDDD8FF), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _purple, width: 1.5),
                  ),
                  prefixIcon: _isFetchingSuggestions
                      ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _purple),
                    ),
                  )
                      : const Icon(Icons.location_on_outlined,
                      color: _purple, size: 20),
                  suffixIcon: _isDetectingLocation
                      ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _purple),
                    ),
                  )
                      : IconButton(
                    tooltip: 'Use current location',
                    icon: const Icon(Icons.my_location,
                        color: _purple, size: 20),
                    onPressed: _getCurrentLocation,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text('Ad Validity',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87)),
            const SizedBox(height: 4),
            Text(
              'Resets the expiry countdown from today.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.durationDays.keys.map((label) {
                final isSelected = _duration == label;
                return GestureDetector(
                  onTap: () => setState(() => _duration = label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _purple : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? _purple : const Color(0xFFDDD8FF),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  if (_adSize == null ||
                      _locationController.text.trim().isEmpty) {
                    _showSnack('Please fill all fields', error: true);
                    return;
                  }
                  final adSize = _adSize!;
                  final location = _locationController.text.trim();
                  final duration = _duration;
                  final lat = _latitude;
                  final lng = _longitude;
                  Navigator.pop(context);
                  await widget.onSave(
                    doc: widget.doc,
                    adSize: adSize,
                    location: location,
                    duration: duration,
                    latitude: lat,
                    longitude: lng,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Changes',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}