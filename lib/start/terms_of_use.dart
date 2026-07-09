import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Terms of Use screen for SwapNow (com.credbro.app).
///
/// Visual language matches the rest of the app:
/// - Lavender background
/// - White content card
/// - Purple gradient app bar
///
/// NOTE: This is a template. Replace the placeholder values below
/// (company name, contact email, governing law, effective date) with
/// your actual legal details, and have it reviewed by counsel before
/// publishing — this text is a starting point, not legal advice.
class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  // ---- Editable constants -------------------------------------------------
  static const String appName = 'SwapNow';
  static const String companyName = 'SwapNow Pvt Ltd.';
  static const String supportEmail = 'swapnowofficial@gmail.com';
  static const String effectiveDate = 'July 1, 2026';
  static const String governingLaw = 'India';

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
                'Terms of Use',
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
                      'These Terms of Use ("Terms") govern your access to and use of '
                          '$appName (the "Service"), operated by $companyName ("we", "us", '
                          '"our"). By creating an account or using the Service, you agree '
                          'to be bound by these Terms.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    _Section(
                      title: '1. Eligibility',
                      children: [
                        _Bullet('You must be at least 18 years old, or the age of '
                            'legal majority in your jurisdiction, to create an account '
                            'and use $appName.'),
                        _Bullet('By using the Service, you represent that you have the '
                            'legal capacity to enter into these Terms.'),
                      ],
                    ),

                    _Section(
                      title: '2. Your Account',
                      children: [
                        _Bullet('You are responsible for maintaining the '
                            'confidentiality of your login credentials and for all '
                            'activity that occurs under your account.'),
                        _Bullet('You agree to provide accurate, current, and complete '
                            'information during registration and to keep it updated.'),
                        _Bullet('We reserve the right to suspend or terminate accounts '
                            'that violate these Terms.'),
                      ],
                    ),

                    _Section(
                      title: '3. Listings and Product Swaps',
                      children: [
                        _Bullet('$appName is a marketplace that lets users list, '
                            'browse, swap, and purchase products from other users.'),
                        _Bullet('You are solely responsible for the accuracy of your '
                            'listings, including descriptions, condition, pricing, and '
                            'photos.'),
                        _Bullet('You may not list items that are illegal, stolen, '
                            'counterfeit, hazardous, or that infringe on the '
                            'intellectual property rights of others.'),
                        _Bullet('We do not own, inspect, or take title to any items '
                            'listed on the Service. Transactions occur directly '
                            'between users.'),
                        _Bullet('We are not a party to any swap or sale agreement '
                            'between users and are not responsible for the quality, '
                            'safety, legality, or delivery of listed items.'),
                      ],
                    ),

                    _Section(
                      title: '4. Payments',
                      children: [
                        _Bullet('Certain features or transactions may require payment '
                            'processed through Razorpay. By making a payment, you '
                            'agree to Razorpay\'s applicable terms and policies.'),
                        _Bullet('All fees are disclosed prior to payment. Fees are '
                            'generally non-refundable except as required by law or as '
                            'expressly stated in the app.'),
                        _Bullet('You are responsible for any taxes applicable to your '
                            'transactions.'),
                      ],
                    ),

                    _Section(
                      title: '5. User Conduct',
                      children: [
                        _Bullet('You agree not to use the Service to harass, threaten, '
                            'defraud, or mislead other users.'),
                        _Bullet('You agree not to post false, misleading, defamatory, '
                            'or infringing content.'),
                        _Bullet('You agree not to attempt to interfere with, disrupt, '
                            'or gain unauthorized access to the Service, its servers, '
                            'or connected networks.'),
                        _Bullet('You agree not to use bots, scrapers, or automated '
                            'tools to access the Service without our written '
                            'permission.'),
                        _Bullet('We may remove content or suspend accounts that '
                            'violate this section, at our discretion.'),
                      ],
                    ),

                    _Section(
                      title: '6. In-App Messaging',
                      children: [
                        _Bullet('The chat feature is provided to facilitate '
                            'communication between users about listings. Do not use it '
                            'to share sensitive personal or financial information '
                            'beyond what is necessary to complete a transaction.'),
                        _Bullet('We are not responsible for the content of messages '
                            'exchanged between users, but may review messages to '
                            'investigate reported abuse or enforce these Terms.'),
                      ],
                    ),

                    _Section(
                      title: '7. Advertisements',
                      children: [
                        _Bullet('The Service may display advertisements served '
                            'through Google AdMob. We are not responsible for the '
                            'content of third-party advertisements.'),
                      ],
                    ),

                    _Section(
                      title: '8. Intellectual Property',
                      children: [
                        _Bullet('The Service, including its design, logos, and '
                            'branding, is owned by $companyName and protected by '
                            'applicable intellectual property laws.'),
                        _Bullet('By posting content (including listing photos and '
                            'descriptions), you grant us a non-exclusive, worldwide, '
                            'royalty-free license to host, display, and distribute '
                            'that content solely for the purpose of operating and '
                            'promoting the Service.'),
                        _Bullet('You retain ownership of the content you post.'),
                      ],
                    ),

                    _Section(
                      title: '9. Disclaimers',
                      children: [
                        _Bullet('The Service is provided "as is" and "as available" '
                            'without warranties of any kind, express or implied, '
                            'including merchantability, fitness for a particular '
                            'purpose, and non-infringement.'),
                        _Bullet('We do not guarantee the accuracy, quality, safety, or '
                            'legality of listings posted by users, or that any swap or '
                            'sale will be completed successfully.'),
                        _Bullet('You use the Service, and interact with other users, '
                            'at your own risk. We strongly recommend meeting in safe, '
                            'public locations for in-person exchanges.'),
                      ],
                    ),

                    _Section(
                      title: '10. Limitation of Liability',
                      children: [
                        _Bullet('To the maximum extent permitted by law, '
                            '$companyName shall not be liable for any indirect, '
                            'incidental, special, consequential, or punitive damages '
                            'arising from your use of the Service, or from any '
                            'transaction or dispute between users.'),
                        _Bullet('Our total liability for any claim arising from these '
                            'Terms or the Service shall not exceed the amount you paid '
                            'us, if any, in the six months preceding the claim.'),
                      ],
                    ),

                    _Section(
                      title: '11. Indemnification',
                      children: [
                        _Bullet('You agree to indemnify and hold $companyName '
                            'harmless from any claims, damages, losses, or expenses '
                            'arising from your use of the Service, your listings, or '
                            'your violation of these Terms.'),
                      ],
                    ),

                    _Section(
                      title: '12. Termination',
                      children: [
                        _Bullet('We may suspend or terminate your access to the '
                            'Service at any time, with or without notice, for conduct '
                            'that we believe violates these Terms or is harmful to '
                            'other users or the Service.'),
                        _Bullet('You may stop using the Service and request account '
                            'deletion at any time by contacting $supportEmail.'),
                      ],
                    ),

                    _Section(
                      title: '13. Changes to These Terms',
                      children: [
                        _Bullet('We may update these Terms from time to time. '
                            'Continued use of the Service after changes take effect '
                            'constitutes acceptance of the revised Terms.'),
                      ],
                    ),

                    _Section(
                      title: '14. Governing Law',
                      children: [
                        _Bullet('These Terms are governed by the laws of '
                            '$governingLaw, without regard to conflict-of-law '
                            'principles.'),
                      ],
                    ),

                    _Section(
                      title: '15. Contact Us',
                      children: [
                        const Text(
                          'If you have questions about these Terms, contact us at:',
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
                        const SizedBox(height: 8),
                        Text(
                          companyName,
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
// Shared small widgets (private to this file).
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
              color: TermsOfUsePage._textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
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
                color: TermsOfUsePage._purpleLight,
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
                color: TermsOfUsePage._textPrimary,
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
            Icon(icon, size: 18, color: TermsOfUsePage._purpleDark),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: TermsOfUsePage._purpleDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}