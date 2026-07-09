import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/admin%20panel/ad_response.dart';
import 'package:credbro/custom_loader.dart';
import 'package:credbro/help/help_center.dart';
import 'package:credbro/pages/payments_details.dart';
import 'package:credbro/pages/profilepage.dart';
import 'package:credbro/pages/want_to_advertise.dart';
import 'package:credbro/pages/wishlistpage.dart';
import 'package:credbro/start/privacy_policy.dart';
import 'package:credbro/start/suggestion.dart';
import 'package:credbro/start/terms_of_use.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../logs/otp.dart';
import 'my_products.dart';

class ProfilePageScreen extends StatefulWidget {
  const ProfilePageScreen({super.key});

  @override
  State<ProfilePageScreen> createState() => _ProfilePageScreenState();
}

class _ProfilePageScreenState extends State<ProfilePageScreen> {
  static const Color _primary = Color(0xFF5800B3);

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1B8A4C),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    _showSuccessSnack("Logout successful");
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OtpSignupPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final hPad = (size.width * 0.04).clamp(12.0, 32.0);
    final avatarRadius = isTablet ? 44.0 : (size.width * 0.09).clamp(30.0, 40.0);
    final nameFontSize = (size.width * 0.045).clamp(15.0, 20.0);
    final emailFontSize = (size.width * 0.033).clamp(12.0, 15.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Profile",
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
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser?.uid)
              .snapshots(includeMetadataChanges: true), // reads cache first, then server
          builder: (context, snapshot) {
            final data = (snapshot.hasData
                ? snapshot.data!.data() as Map<String, dynamic>?
                : null) ?? {};

            final name = data['name'] ?? "User Name";
            final email = data['email'] ?? "email@example.com";
            final image = data['profileImage'] as String?;

            return Column(
              children: [
                /// ── USER CARD
                Container(
                  margin: EdgeInsets.fromLTRB(hPad, 14, hPad, 0),
                  padding: EdgeInsets.all(isTablet ? 18 : 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF3EEFF), Color(0xFFFFFFFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _primary.withOpacity(0.12),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primary.withOpacity(0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7B10E8), Color(0xFF26004D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: Colors.white,
                          backgroundImage: (image != null && image.isNotEmpty)
                              ? NetworkImage(image)
                              : null,
                          child: (image == null || image.isEmpty)
                              ? Icon(Icons.person,
                              size: avatarRadius * 1.1, color: _primary)
                              : null,
                        ),
                      ),
                      SizedBox(width: isTablet ? 16 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: nameFontSize,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: emailFontSize,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                /// ── LIST
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                        horizontal: hPad - 4, vertical: 4),
                    children: [
                      _sectionTitle("Account", size),
                      _tile(Icons.person_2_outlined, "Manage Profile",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ProfilePage()))),
                      _tile(Icons.shopping_cart_outlined, "Want to Advertise?",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const WantToAdvertisePage()))),
                      _tile(Icons.shopping_cart_outlined, "Advertisement Responses",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AdResponsesPage()))),
                      _tile(Icons.payment_outlined, "Payment History",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const PaymentsDetails()))),
                      _tile(Icons.shopping_bag_outlined, "My Products",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const MyProductsPage()))),
                      _tile(Icons.favorite_outline, "Wishlist",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const WishlistPage()))),

                      _sectionTitle("Preferences", size),
                      _tile(Icons.policy_outlined, "Privacy Policy",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const PrivacyPolicyPage()))),
                      _tile(Icons.security, "Terms of Use",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const TermsOfUsePage()))),
                      _sectionTitle("Support", size),
                      _tile(
                          Icons.settings_suggest_outlined, "Suggestions",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const SuggestionsPage()))),
                      _tile(Icons.help_outline, "Help Center",
                          size: size,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                  const HelpCenterPage()))),
                      _tile(Icons.logout, "Logout",
                          size: size,
                          isDestructive: true,
                          onTap: _logout),

                      const SizedBox(height: 16),
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

  Widget _sectionTitle(String title, Size size) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: (size.width * 0.03).clamp(11.0, 13.0),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
      IconData icon,
      String title, {
        required Size size,
        VoidCallback? onTap,
        bool isDestructive = false,
      }) {
    final tileColor = isDestructive
        ? const Color(0xFFFF3B30).withOpacity(0.07)
        : Colors.white;
    final iconColor =
    isDestructive ? const Color(0xFFFF3B30) : _primary;
    final textColor =
    isDestructive ? const Color(0xFFFF3B30) : const Color(0xFF1A1A2E);
    final tileFontSize = (size.width * 0.038).clamp(13.0, 16.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDestructive
              ? const Color(0xFFFF3B30).withOpacity(0.15)
              : const Color(0xFFEDE8F5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (size.width * 0.04).clamp(12.0, 20.0),
              vertical: (size.height * 0.016).clamp(12.0, 18.0),
            ),
            child: Row(
              children: [
                Container(
                  width: (size.width * 0.09).clamp(34.0, 44.0),
                  height: (size.width * 0.09).clamp(34.0, 44.0),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: (size.width * 0.05).clamp(18.0, 22.0),
                      color: iconColor),
                ),
                SizedBox(width: (size.width * 0.035).clamp(10.0, 16.0)),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: tileFontSize,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: (size.width * 0.055).clamp(18.0, 24.0),
                  color: isDestructive
                      ? const Color(0xFFFF3B30).withOpacity(0.5)
                      : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}