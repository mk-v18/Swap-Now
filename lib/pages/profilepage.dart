import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color _primary = Color(0xFF5800B3);

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  final FocusNode _locationFocusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  bool _isLoading = true;
  bool _isDetectingLocation = false;
  bool _isSaving = false;

  List<String> _suggestions = [];
  // FIX(gap): this page never captured coordinates at all — GPS detect
  // only produced a display string, and the saved 'location' field was
  // string-only, so re-editing a profile here could never restore a
  // product/home page's ability to sort by distance from the user.
  List<Map<String, double>?> _suggestionCoords = [];
  double? _latitude;
  double? _longitude;
  Timer? _debounce;
  bool _isFetchingSuggestions = false;

  File? _pickedImage;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _locationFocusNode.addListener(() {
      if (!_locationFocusNode.hasFocus) _removeOverlay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _locationFocusNode.dispose();
    _nameController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ─── Overlay ──────────────────────────────────────────────────────────────────

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;

    final size = MediaQuery.of(context).size;
    final hPad = (size.width * 0.06).clamp(20.0, 48.0);

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: size.width - (hPad * 2),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 60),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            shadowColor: _primary.withOpacity(0.15),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) {
                final isFirst = i == 0;
                final isLast = i == _suggestions.length - 1;
                return InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: isFirst ? const Radius.circular(14) : Radius.zero,
                    bottom: isLast ? const Radius.circular(14) : Radius.zero,
                  ),
                  onTap: () => _selectSuggestion(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on_outlined,
                              size: 14, color: _primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _suggestions[i],
                            style: TextStyle(
                              fontSize: (size.width * 0.032).clamp(12.0, 14.0),
                              color: const Color(0xFF1A1A2E),
                            ),
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
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  // ─── Nominatim Autocomplete ───────────────────────────────────────────────────

  void _onLocationChanged(String value) {
    // FIX(gap): manual edits invalidate previously captured coordinates.
    _latitude = null;
    _longitude = null;
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => _fetchSuggestions(value.trim()));
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isFetchingSuggestions = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(input)}'
            '&format=json&limit=5&addressdetails=1',
      );
      final response =
      await http.get(url, headers: {'User-Agent': 'SwapNow/1.0 (com.credbro.app)'});

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _suggestions =
              data.map<String>((item) => item['display_name'] as String).toList();
          // FIX(gap): capture each suggestion's coordinates.
          _suggestionCoords = data.map<Map<String, double>?>((item) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat == null || lon == null) return null;
            return {'lat': lat, 'lng': lon};
          }).toList();
        });
        _showOverlay();
      } else {
        setState(() { _suggestions = []; _suggestionCoords = []; });
        _removeOverlay();
      }
    } catch (_) {
      setState(() { _suggestions = []; _suggestionCoords = []; });
      _removeOverlay();
    } finally {
      setState(() => _isFetchingSuggestions = false);
    }
  }

  void _selectSuggestion(int index) {
    if (index < 0 || index >= _suggestions.length) return;
    final suggestion = _suggestions[index];
    final parts = suggestion.split(',').map((s) => s.trim()).toList();
    final coords = index < _suggestionCoords.length ? _suggestionCoords[index] : null;
    _locationController.text = parts.take(3).join(', ');
    // FIX(gap): persist the coordinates that came with this suggestion.
    _latitude = coords?['lat'];
    _longitude = coords?['lng'];
    _locationFocusNode.unfocus();
    setState(() { _suggestions = []; _suggestionCoords = []; });
    _removeOverlay();
  }

  // ─── GPS ──────────────────────────────────────────────────────────────────────

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) return;
      }

      setState(() => _isDetectingLocation = true);
      _removeOverlay();

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks =
      await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _locationController.text =
          "${place.locality}, ${place.administrativeArea}, ${place.country}";
          _suggestions = [];
          _suggestionCoords = [];
          // FIX(gap): keep the exact GPS coordinates.
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        _showSuccessSnack("Location updated successfully!");
      }
    } catch (_) {
      _showErrorSnack("Location error. Try again.");
    } finally {
      setState(() => _isDetectingLocation = false);
    }
  }

  // ─── Firebase ────────────────────────────────────────────────────────────────

  Future<void> _fetchUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        _nameController.text = data['name'] ?? '';
        _locationController.text = data['location'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _emailController.text = data['email'] ?? '';
        _imageUrl = data['profileImage'];
        // FIX(gap): preload existing coordinates so re-saving without
        // touching the location field doesn't wipe them out below.
        final savedLat = data['lat'];
        final savedLng = data['lng'];
        _latitude  = savedLat is num ? savedLat.toDouble() : null;
        _longitude = savedLng is num ? savedLng.toDouble() : null;
      }
    } catch (_) {
      _showErrorSnack("Error loading profile");
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    final picked =
    await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    String? imageUrl = _imageUrl;

    try {
      if (_pickedImage != null && uid != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('user_images')
            .child('$uid.jpg');
        await ref.putFile(_pickedImage!);
        imageUrl = await ref.getDownloadURL();
      }

      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'name': _nameController.text.trim(),
          'location': _locationController.text.trim(),
          // FIX(gap): persist coordinates alongside the location string.
          'lat': _latitude,
          'lng': _longitude,
          'email': _emailController.text.trim(), // ✅ email now saved
          'profileImage': imageUrl,
        });
      }

      setState(() {
        _imageUrl = imageUrl;
        _pickedImage = null;
      });
      _showSuccessSnack("Profile updated successfully!");
    } catch (_) {
      _showErrorSnack("Failed to save changes");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── Snacks ──────────────────────────────────────────────────────────────────

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: const Color(0xFF1B8A4C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ));
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: const Color(0xFFB00020),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hPad = (size.width * 0.06).clamp(20.0, 48.0);
    final avatarRadius = (size.width * 0.14).clamp(44.0, 64.0);
    final labelFontSize = (size.width * 0.036).clamp(13.0, 15.0);
    final buttonHeight = (size.height * 0.068).clamp(50.0, 64.0);
    final buttonFontSize = (size.width * 0.042).clamp(14.0, 17.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Profile Details",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.black, size: 18),
            onPressed: () {
              Navigator.pop(context);
            }
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: _primary),
      )
          : SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: hPad, vertical: size.height * 0.025),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Avatar
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Gradient ring
                    Container(
                      width: avatarRadius * 2 + 8,
                      height: avatarRadius * 2 + 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B10E8), Color(0xFF26004D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _pickedImage != null
                          ? FileImage(_pickedImage!) as ImageProvider
                          : (_imageUrl != null && _imageUrl!.isNotEmpty
                          ? NetworkImage(_imageUrl!)
                          : null),
                      child: (_pickedImage == null &&
                          (_imageUrl == null || _imageUrl!.isEmpty))
                          ? Icon(Icons.person,
                          size: avatarRadius * 0.9,
                          color: Colors.white70)
                          : null,
                    ),
                    // Camera badge
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: _primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 15),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: size.height * 0.03),

              // ── Fields
              _buildTextField(
                "Full Name",
                _nameController,
                icon: Icons.person_outline_rounded,
                labelFontSize: labelFontSize,
                size: size,
              ),
              SizedBox(height: size.height * 0.018),

              _buildLocationField(labelFontSize: labelFontSize, size: size),
              SizedBox(height: size.height * 0.018),

              _buildTextField(
                "Mobile No",
                _phoneController,
                icon: Icons.phone_outlined,
                enabled: false,
                labelFontSize: labelFontSize,
                size: size,
              ),
              SizedBox(height: size.height * 0.018),

              // ✅ Email is now editable
              _buildTextField(
                "Email",
                _emailController,
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                labelFontSize: labelFontSize,
                size: size,
              ),

              SizedBox(height: size.height * 0.04),

              // ── Save button
              Container(
                width: double.infinity,
                height: buttonHeight,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B10E8), Color(0xFF5800B3), Color(0xFF26004D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Save Changes",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: buttonFontSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: size.height * 0.025),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Location field ───────────────────────────────────────────────────────────

  Widget _buildLocationField(
      {required double labelFontSize, required Size size}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel("Location", labelFontSize),
        SizedBox(height: size.height * 0.008),
        CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            controller: _locationController,
            focusNode: _locationFocusNode,
            keyboardType: TextInputType.streetAddress,
            onChanged: _onLocationChanged,
            style: TextStyle(
                fontSize: (size.width * 0.037).clamp(13.0, 15.0),
                color: const Color(0xFF1A1A2E)),
            decoration: _inputDecoration(
              size: size,
              prefixIcon: _isFetchingSuggestions
                  ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _primary),
                ),
              )
                  : const Icon(Icons.location_on_outlined,
                  color: _primary, size: 20),
              suffixIcon: _isDetectingLocation
                  ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _primary),
                ),
              )
                  : IconButton(
                tooltip: "Use current location",
                icon: const Icon(Icons.my_location_rounded,
                    color: _primary, size: 20),
                onPressed: _getLocation,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Generic field ────────────────────────────────────────────────────────────

  Widget _buildTextField(
      String label,
      TextEditingController controller, {
        required double labelFontSize,
        required Size size,
        bool enabled = true,
        IconData? icon,
        TextInputType? keyboardType,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, labelFontSize),
        SizedBox(height: size.height * 0.008),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: (size.width * 0.037).clamp(13.0, 15.0),
            color: enabled ? const Color(0xFF1A1A2E) : Colors.grey.shade600,
          ),
          decoration: _inputDecoration(
            size: size,
            prefixIcon: icon != null
                ? Icon(icon,
                color: enabled ? _primary : Colors.grey.shade400, size: 20)
                : null,
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFF2F0F7),
          ),
        ),
      ],
    );
  }

  // ─── Shared input decoration ──────────────────────────────────────────────────

  InputDecoration _inputDecoration({
    required Size size,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool filled = true,
    Color fillColor = Colors.white,
  }) {
    return InputDecoration(
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: filled,
      fillColor: fillColor,
      contentPadding: EdgeInsets.symmetric(
        vertical: (size.height * 0.018).clamp(14.0, 20.0),
        horizontal: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDD6F0), width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDD6F0), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
    );
  }

  // ─── Label helper ─────────────────────────────────────────────────────────────

  Widget _fieldLabel(String label, double fontSize) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: const Color(0xFF1A1A2E),
        letterSpacing: 0.1,
      ),
    );
  }
}