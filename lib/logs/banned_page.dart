import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/logs/otp.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../help/help_center.dart';

/// Full-screen block shown instead of the normal app when the user's
/// account has been banned. Stays up until an admin unbans them (handled
/// live by BannedGate) or they sign out.
class AccountBannedPage extends StatelessWidget {
  const AccountBannedPage({super.key});

  static const _purple      = Color(0xFF5800B3);
  static const _purpleDark  = Color(0xFF26004D);

  // TODO: point this at your illustration asset, e.g. add to pubspec.yaml:
  //   assets:
  //     - assets/images/account_banned.png
  static const _illustrationAsset = 'assets/images/account_banned.png';

  // Banned users can still open the in-app Help Center to submit/track an
  // appeal — this is the primary path now instead of relying on email.
  void _openHelpCenter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HelpCenterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3E5F5),
              Color(0xFFFFFFFF),
            ],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Illustration
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _purple.withOpacity(0.10),
                            _purple.withOpacity(0.0),
                          ],
                        ),
                      ),
                      child: Center(
                        child: ClipOval(
                          child: Container(
                            width: 148,
                            height: 148,
                            color: Colors.white,
                            padding: const EdgeInsets.all(20),
                            child: Image.asset(
                              _illustrationAsset,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                // Falls back gracefully if the asset hasn't
                                // been added yet.
                                return Icon(
                                  Icons.block_rounded,
                                  color: Colors.red.shade400,
                                  size: 56,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text(
                      'Account Restricted',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text(
                      'Your account has been restricted due to a violation '
                          'of our community guidelines. You won\'t be able to '
                          'use SwapNow until this is resolved. You can still '
                          'submit an appeal through the Help Center below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: Colors.grey[600],
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Card wrapping the actions for a bit more separation
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [_purple, _purpleDark],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _purple.withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _openHelpCenter(context),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 15),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
                                        SizedBox(width: 10),
                                        Text(
                                          'Contact Help Center',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Divider(height: 20),
                          TextButton.icon(
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const OtpSignupPage()),
                                      (route) => false,
                                );
                              }
                            },
                            icon: Icon(Icons.logout_rounded, size: 18, color: Colors.grey[500]),
                            label: Text(
                              'Sign Out',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] and live-watches the user's Firestore doc. The moment
/// `banned` flips to true (even mid-session), this swaps to
/// [AccountBannedPage] without needing an app restart. When unbanned,
/// [child] is shown again automatically.
class BannedGate extends StatelessWidget {
  final String uid;
  final Widget child;

  const BannedGate({super.key, required this.uid, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          if (data['banned'] == true) {
            return const AccountBannedPage();
          }
        }
        return child;
      },
    );
  }
}