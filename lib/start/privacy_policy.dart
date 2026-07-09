import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Privacy Policy screen for SwapNow (com.credbro.app).
///
/// Visual language matches the rest of the app:
/// - Lavender background
/// - White content card
/// - Purple gradient app bar
///
/// NOTE: This is a template. Replace the placeholder values below
/// (company name, contact email, address, effective date) with your
/// actual legal details, and have it reviewed by counsel before
/// publishing — this text is a starting point, not legal advice.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  // ---- Editable constants -------------------------------------------------
  static const String appName = 'SwapNow';
  static const String companyName = 'SwapNow Pvt Ltd.';
  static const String supportEmail = 'swapnowofficial@gmail.com';
  static const String effectiveDate = 'July 1, 2026';
  static const String websiteUrl = 'https://swapnow.in';

  // ---- Design tokens (mirrors app-wide purple/lavender system) -----------
  static const Color _bgLavender = Color(0xFFFFFFFF);
  static const Color _purpleDark = Color(0xFF6A3DE8);
  static const Color _purpleLight = Color(0xFF9C6BFF);
  static const Color _textPrimary = Color(0xFF241F3D);
  static const Color _textSecondary = Color(0xFF6E6785);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgLavender,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: _purpleDark,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 46, right: 16, bottom: 16),
              title: const Text(
                'Privacy Policy',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_purpleDark, _purpleLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Effective date: $effectiveDate',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This Privacy Policy explains how $appName ("we", "us", "our") '
                          'collects, uses, shares, and protects information when you use '
                          'our mobile application and related services (the "Service").',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    _Section(
                      title: '1. Information We Collect',
                      children: [
                        _SubHeading('a. Information you provide'),
                        _Bullet('Account details: name, email address, phone number, '
                            'profile photo, and password (via Firebase Authentication).'),
                        _Bullet('Listing content: product titles, descriptions, prices, '
                            'categories, condition, and photos you upload.'),
                        _Bullet('Communications: messages sent through in-app chat with '
                            'other users or with support.'),
                        _Bullet('Payment information: when you make a payment through '
                            'Razorpay, payment details are collected and processed by '
                            'Razorpay directly. We do not store your full card, UPI, or '
                            'bank account credentials on our servers.'),
                        _SubHeading('b. Information collected automatically'),
                        _Bullet('Device information: device model, operating system, '
                            'unique device identifiers, and app version.'),
                        _Bullet('Usage data: pages viewed, listings interacted with, '
                            'search queries, and general app activity.'),
                        _Bullet('Approximate location: if you grant permission, we use '
                            'location data (including via geocoding services) to show '
                            'nearby listings and estimate distances.'),
                        _Bullet('Advertising identifiers: used by Google AdMob to serve '
                            'and measure ads within the app.'),
                      ],
                    ),

                    _Section(
                      title: '2. How We Use Your Information',
                      children: [
                        _Bullet('To create and manage your account.'),
                        _Bullet('To let you list, browse, search, and swap or purchase '
                            'products.'),
                        _Bullet('To enable messaging between buyers and sellers.'),
                        _Bullet('To process payments and prevent fraud.'),
                        _Bullet('To show relevant listings based on your approximate '
                            'location.'),
                        _Bullet('To personalize and measure advertising.'),
                        _Bullet('To send important notices, security alerts, and support '
                            'messages.'),
                        _Bullet('To maintain the safety, security, and integrity of the '
                            'Service, including moderating listings and enforcing our '
                            'Terms of Use.'),
                      ],
                    ),

                    _Section(
                      title: '3. How We Share Information',
                      children: [
                        _Bullet('With other users: your public profile, listings, and '
                            'chat messages are visible to users you interact with.'),
                        _Bullet('Service providers: we use Firebase (Google) for '
                            'authentication, database, and file storage, and Razorpay '
                            'for payment processing. These providers process data on '
                            'our behalf under their own privacy and security terms.'),
                        _Bullet('Advertising partners: Google AdMob may collect and use '
                            'data to serve ads; see Google\'s Privacy Policy for details.'),
                        _Bullet('Legal reasons: we may disclose information if required '
                            'by law, regulation, legal process, or governmental request.'),
                        _Bullet('Business transfers: information may be transferred in '
                            'connection with a merger, acquisition, or sale of assets.'),
                        _Bullet('We do not sell your personal information to third '
                            'parties.'),
                      ],
                    ),

                    _Section(
                      title: '4. Data Storage and Security',
                      children: [
                        _Bullet('Your data is stored using Firebase infrastructure '
                            '(Firestore, Firebase Storage, Firebase Authentication), '
                            'which applies industry-standard security controls.'),
                        _Bullet('We take reasonable technical and organizational '
                            'measures to protect your information, but no method of '
                            'transmission or storage is 100% secure.'),
                        _Bullet('You are responsible for keeping your account '
                            'credentials confidential.'),
                      ],
                    ),

                    _Section(
                      title: '5. Your Choices and Rights',
                      children: [
                        _Bullet('Access and update: you can review and edit your '
                            'profile and listing information within the app.'),
                        _Bullet('Location permission: you can disable location access '
                            'in your device settings at any time; some features may be '
                            'limited as a result.'),
                        _Bullet('Notifications: you can manage push notification '
                            'preferences in your device settings.'),
                        _Bullet('Account deletion: you may request deletion of your '
                            'account and associated data by contacting us at '
                            '$supportEmail.'),
                        _Bullet('Depending on your location, you may have additional '
                            'rights under applicable data protection laws, including '
                            'the right to request access to, correction of, or erasure '
                            'of your personal data.'),
                      ],
                    ),

                    _Section(
                      title: '6. Children\'s Privacy',
                      children: [
                        _Bullet('$appName is not directed at children under 13 (or the '
                            'minimum age required in your jurisdiction), and we do not '
                            'knowingly collect personal information from children. If '
                            'you believe a child has provided us with personal '
                            'information, please contact us so we can take appropriate '
                            'action.'),
                      ],
                    ),

                    _Section(
                      title: '7. Data Retention',
                      children: [
                        _Bullet('We retain your information for as long as your account '
                            'is active or as needed to provide the Service, comply with '
                            'legal obligations, resolve disputes, and enforce our '
                            'agreements.'),
                      ],
                    ),

                    _Section(
                      title: '8. International Data Transfers',
                      children: [
                        _Bullet('Your information may be stored and processed in '
                            'countries other than your own, including through our use '
                            'of Firebase and other service providers. By using the '
                            'Service, you consent to this transfer.'),
                      ],
                    ),

                    _Section(
                      title: '9. Changes to This Policy',
                      children: [
                        _Bullet('We may update this Privacy Policy from time to time. '
                            'We will notify you of material changes by posting the new '
                            'policy in the app and updating the effective date above.'),
                      ],
                    ),

                    _Section(
                      title: '10. Contact Us',
                      children: [
                        const Text(
                          'If you have questions about this Privacy Policy or how we '
                              'handle your data, contact us at:',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ContactLink(
                          icon: Icons.email_outlined,
                          label: supportEmail,
                          onTap: () => launchUrl(
                            Uri.parse('mailto:$supportEmail'),
                          ),
                        ),
                        _ContactLink(
                          icon: Icons.public,
                          label: websiteUrl,
                          onTap: () => launchUrl(
                            Uri.parse(websiteUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$companyName',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets (kept private to this file; duplicated intentionally
// in terms_of_use_page.dart so each file can be dropped in independently).
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PrivacyPolicyPage._textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SubHeading extends StatelessWidget {
  final String text;
  const _SubHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: PrivacyPolicyPage._textPrimary,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: PrivacyPolicyPage._purpleLight,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: PrivacyPolicyPage._textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContactLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: PrivacyPolicyPage._purpleDark),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: PrivacyPolicyPage._purpleDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}