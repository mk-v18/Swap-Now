import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/custom_loader.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../logs/otp.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final _nameController     = TextEditingController();
  final _phoneController    = TextEditingController();
  final _locationController = TextEditingController();

  bool _isEditing = false;
  bool _isSaving  = false;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _lightPurple = Color(0xFFEDE7F6);
  static const _lavender    = Color(0xFFFAF5FF);
  static const _green       = Color(0xFF1B8A4C);
  static const _red         = Color(0xFFB00020);

  // ── Responsive helpers ─────────────────────────────────────────────────────
  double _clamp(double v, double mn, double mx) =>
      v < mn ? mn : (v > mx ? mx : v);

  double _rw(BuildContext ctx, double f, {double min = 0, double max = 9999}) =>
      _clamp(MediaQuery.of(ctx).size.width * f, min, max);

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // ── Snackbars ──────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool error = false}) {
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
            child: Text(msg,
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

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Name cannot be empty', error: true);
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _showSnack('Phone cannot be empty', error: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name':     _nameController.text.trim(),
        'phone':    _phoneController.text.trim(),
        'location': _locationController.text.trim(),
      });
      setState(() {
        _isEditing = false;
        _isSaving  = false;
      });
      _showSnack('Profile updated successfully');
    } catch (_) {
      setState(() => _isSaving = false);
      _showSnack('Failed to update profile', error: true);
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => _LogoutDialog(),
    );
    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance.signOut();
      _showSnack('Logout successful');
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OtpSignupPage()),
      );
    } catch (_) {
      _showSnack('Error logging out', error: true);
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

    // Responsive sizing
    final hPad        = _clamp(screenW * 0.045, 14.0, 28.0);
    final avatarR     = _clamp(screenW * 0.11,  38.0, 56.0);
    final nameFontSz  = _clamp(screenW * 0.048, 16.0, 22.0);
    final emailFontSz = _clamp(screenW * 0.035, 12.0, 15.0);
    final labelFontSz = _clamp(screenW * 0.032, 11.0, 14.0);
    final valueFontSz = _clamp(screenW * 0.038, 13.0, 16.0);
    final sectionFontSz = _clamp(screenW * 0.033, 11.0, 14.0);
    final iconSz      = _clamp(screenW * 0.055, 18.0, 24.0);
    final cardRadius  = _clamp(screenW * 0.04,  12.0, 18.0);
    final btnFontSz   = _clamp(screenW * 0.042, 14.0, 17.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFFF),
      appBar: _buildAppBar(screenW),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CustomLoader());
            }

            final raw  = snapshot.data!.data();
            if (raw == null) {
              return const Center(child: Text('No profile data found.'));
            }
            final data = raw as Map<String, dynamic>;

            final name     = data['name']         ?? 'Admin';
            final email    = data['email']        ?? 'email@example.com';
            final phone    = data['phone']        ?? 'N/A';
            final location = data['location']     ?? 'N/A';
            final role     = data['role']         ?? 'admin';
            final image    = data['profileImage'] as String?;

            // Populate controllers when not in edit mode
            if (!_isEditing) {
              _nameController.text     = name;
              _phoneController.text    = phone;
              _locationController.text = location;
            }

            // Format createdAt
            String createdAt = 'N/A';
            if (data['createdAt'] != null) {
              final dt = (data['createdAt'] as Timestamp).toDate();
              createdAt =
              '${dt.day}/${dt.month}/${dt.year}  '
                  '${dt.hour.toString().padLeft(2, '0')}:'
                  '${dt.minute.toString().padLeft(2, '0')}';
            }

            return Column(
              children: [
                // ── Hero card ───────────────────────────────────────────────
                _buildHeroCard(
                  context,
                  image:       image,
                  name:        name,
                  email:       email,
                  role:        role,
                  hPad:        hPad,
                  avatarR:     avatarR,
                  nameFontSz:  nameFontSz,
                  emailFontSz: emailFontSz,
                  cardRadius:  cardRadius,
                ),

                // ── Scrollable body ─────────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                        horizontal: hPad, vertical: 8),
                    children: [
                      // Personal Info
                      _sectionTitle('Personal Info', sectionFontSz),
                      _isEditing
                          ? _editableTile(Icons.person_2_outlined, 'Name',
                          _nameController, TextInputType.name,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius)
                          : _infoTile(Icons.person_2_outlined, 'Name', name,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),

                      _infoTile(Icons.email_outlined, 'Email', email,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),

                      _isEditing
                          ? _editableTile(Icons.phone_outlined, 'Phone',
                          _phoneController, TextInputType.phone,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius)
                          : _infoTile(Icons.phone_outlined, 'Phone', phone,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),

                      _isEditing
                          ? _editableTile(
                          Icons.location_on_outlined, 'Location',
                          _locationController,
                          TextInputType.streetAddress,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius)
                          : _infoTile(Icons.location_on_outlined, 'Location',
                          location,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),

                      // Save button (edit mode)
                      if (_isEditing) ...[
                        const SizedBox(height: 14),
                        _buildSaveButton(btnFontSz: btnFontSz),
                        const SizedBox(height: 4),
                        // Cancel inline
                        TextButton(
                          onPressed: () => setState(() => _isEditing = false),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ],

                      // Account Info
                      _sectionTitle('Account Info', sectionFontSz),
                      _infoTile(Icons.shield_outlined, 'Role',
                          role.toUpperCase(),
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),
                      _infoTile(Icons.calendar_today_outlined, 'Member Since',
                          createdAt,
                          iconSz: iconSz,
                          labelFontSz: labelFontSz,
                          valueFontSz: valueFontSz,
                          cardRadius: cardRadius),

                      // Actions
                      _sectionTitle('Actions', sectionFontSz),
                      _buildLogoutTile(
                          cardRadius: cardRadius,
                          valueFontSz: valueFontSz,
                          iconSz: iconSz),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(double screenW) {
    final titleSz = _clamp(screenW * 0.05, 17.0, 22.0);
    return AppBar(
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFFFFFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        'Admin Profile',
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
      actions: [
        if (!_isEditing)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined,
                  size: 17, color: _purple),
              label: const Text(
                'Edit',
                style: TextStyle(
                    color: _purple, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: TextButton.styleFrom(
                backgroundColor: _lightPurple,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
      ],
    );
  }

  // ── Hero card ──────────────────────────────────────────────────────────────
  Widget _buildHeroCard(
      BuildContext context, {
        required String? image,
        required String name,
        required String email,
        required String role,
        required double hPad,
        required double avatarR,
        required double nameFontSz,
        required double emailFontSz,
        required double cardRadius,
      }) {
    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 4, hPad, 0),
      padding: EdgeInsets.all(_clamp(hPad * 0.8, 12.0, 20.0)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_purple, _deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(cardRadius + 4),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar with white ring
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.25),
            ),
            child: CircleAvatar(
              radius: avatarR,
              backgroundImage: (image != null && image.isNotEmpty)
                  ? NetworkImage(image)
                  : null,
              backgroundColor: _lightPurple,
              child: (image == null || image.isEmpty)
                  ? Icon(Icons.admin_panel_settings,
                  color: _purple, size: avatarR * 0.7)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: nameFontSz,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: emailFontSz,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.4), width: 1),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section title ──────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, double fontSize) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ── Info tile (read-only) ──────────────────────────────────────────────────
  Widget _infoTile(
      IconData icon,
      String title,
      String value, {
        required double iconSz,
        required double labelFontSz,
        required double valueFontSz,
        required double cardRadius,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: iconSz + 14,
          height: iconSz + 14,
          decoration: BoxDecoration(
            color: _lightPurple,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: iconSz, color: _purple),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: labelFontSz,
                color: Colors.grey,
                fontWeight: FontWeight.w500)),
        subtitle: Text(value,
            style: TextStyle(
                fontSize: valueFontSz,
                color: Colors.black87,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── Editable tile ──────────────────────────────────────────────────────────
  Widget _editableTile(
      IconData icon,
      String label,
      TextEditingController controller,
      TextInputType keyboardType, {
        required double iconSz,
        required double labelFontSz,
        required double valueFontSz,
        required double cardRadius,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _lavender,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: _purple.withOpacity(0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: iconSz + 14,
          height: iconSz + 14,
          decoration: BoxDecoration(
            color: _lightPurple,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: iconSz, color: _purple),
        ),
        title: Text(label,
            style: TextStyle(
                fontSize: labelFontSz,
                color: _purple.withOpacity(0.7),
                fontWeight: FontWeight.w500)),
        subtitle: TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(
              fontSize: valueFontSz,
              color: Colors.black87,
              fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.only(top: 4, bottom: 2),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────
  Widget _buildSaveButton({required double btnFontSz}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveChanges,
        style: ElevatedButton.styleFrom(
          backgroundColor: _purple,
          disabledBackgroundColor: _purple.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 4,
          shadowColor: _purple.withOpacity(0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: _isSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child:
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : Text(
          'Save Changes',
          style: TextStyle(
            color: Colors.white,
            fontSize: btnFontSz,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Logout tile ────────────────────────────────────────────────────────────
  Widget _buildLogoutTile({
    required double cardRadius,
    required double valueFontSz,
    required double iconSz,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1),
        boxShadow: [
          BoxShadow(
            color: _red.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: _logout,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: iconSz + 14,
          height: iconSz + 14,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.logout, size: iconSz, color: _red),
        ),
        title: Text(
          'Logout',
          style: TextStyle(
            color: _red,
            fontWeight: FontWeight.w600,
            fontSize: valueFontSz,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: _red),
      ),
    );
  }
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenWidth < 400 ? 20 : 40,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.logout_rounded,
                        color: scheme.onErrorContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sign out',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "You'll need to verify your phone number again to access your account.",
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign out'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          side: BorderSide(
                            color: scheme.outlineVariant,
                            width: 0.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: textTheme.labelLarge,
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}