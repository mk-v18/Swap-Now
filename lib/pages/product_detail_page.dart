import 'package:credbro/Advertisement/location_ad.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:credbro/chats/chatservice.dart';
import 'package:credbro/chats/chatscreen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS  (copied from UserProductDetailsPage)
// ─────────────────────────────────────────────────────────────────────────────
class _T {
  static const purple      = Color(0xFF6A1B9A);
  static const deepPurple  = Color(0xFF4A148C);
  static const lightPurple = Color(0xFFEDE7F6);
  static const teal        = Color(0xFF00796B);
  static const tealLight   = Color(0xFFE0F2F1);
  static const bg          = Color(0xFFF7F4FB);
  static const cardBg      = Colors.white;
  static const textDark    = Color(0xFF1A1A2E);
  static const textMid     = Color(0xFF555566);
  static const textLight   = Color(0xFF9999AA);
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSIVE HELPER  (copied from UserProductDetailsPage)
// ─────────────────────────────────────────────────────────────────────────────
class _RL {
  final double width;
  final double height;
  const _RL(this.width, this.height);
  factory _RL.of(BuildContext ctx) {
    final s = MediaQuery.of(ctx).size;
    return _RL(s.width, s.height);
  }
  bool get isMobile  => width < 600;
  bool get isTablet  => width >= 600 && width < 900;
  bool get isDesktop => width >= 900;
  double get hPad    => isDesktop ? 48 : (isTablet ? 28 : 16);
  double get carouselH {
    if (isDesktop) return (height * 0.50).clamp(320, 480);
    if (isTablet)  return (height * 0.45).clamp(280, 420);
    return (height * 0.42).clamp(230, 350);
  }
  double get sheetMax   => isMobile ? 0.93 : 0.82;
}
// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ProductDetailPage extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const ProductDetailPage({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();
  bool _isLoading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── SELL TO COMPANY ───────────────────────────────────────────────────────
  Future<void> _sellToCompany() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showErrorSnack("Please login to continue");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final adminUid = await ChatService.getAdminUid();
      if (adminUid == null) {
        _showErrorSnack("Support unavailable. Please try again later.");
        return;
      }

      final adminDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(adminUid)
          .get();

      String adminName  = 'SwapNow Support';
      String adminImage = '';
      if (adminDoc.exists) {
        final d = adminDoc.data()!;
        adminName  = d['name']         ?? 'SwapNow Support';
        adminImage = d['profileImage'] ?? '';
      }

      final chatService = ChatService();
      final chatId =
      await chatService.getOrCreateChat(currentUser.uid, adminUid);

      final productForDb = {
        'id':          widget.productId,
        'title':       widget.data['title']       ?? '',
        'price':       widget.data['price']       ?? '',
        'images':      (widget.data['images'] as List?)?.take(3).toList() ?? [],
        'condition':   widget.data['condition']   ?? '',
        'category':    widget.data['category']    ?? '',
        'location':    widget.data['location']    ?? '',
        'description': widget.data['description'] ?? '',
      };

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .set(
        {
          'intent': {
            'type':          'sell',
            'listedProduct': productForDb,
            'swapProducts':  [],
            'updatedAt':     FieldValue.serverTimestamp(),
          }
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId:        chatId,
            receiverId:    adminUid,
            receiverName:  adminName,
            receiverImage: adminImage,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showErrorSnack("Something went wrong. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── SNACKBARS ─────────────────────────────────────────────────────────────
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
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor: const Color(0xFF1B8A4C),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin:   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor: const Color(0xFFB00020),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin:   const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
      ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rl     = _RL.of(context);
    final images = (widget.data['images'] as List?) ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(rl),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image Carousel ────────────────────────────────────────────
            _buildCarousel(rl, images),

            // ── Dot Indicators ────────────────────────────────────────────
            if (images.length > 1) _buildDots(images.length),
            const SizedBox(height: 16),

            // ── Info Card (title + price + badges) ────────────────────────
            _buildInfoCard(rl),

            const SizedBox(height: 12),

            // ── Meta Card (location + category + condition) ───────────────
            _buildMetaCard(rl),

            const SizedBox(height: 12),

            // ── Description Card ──────────────────────────────────────────
            _buildDescriptionCard(rl),

            const SizedBox(height: 20),

            // ── Ad ────────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: rl.hPad),
              child: const LocationAdWidget(
                  targetAdSize: 'Large Banner (320×100)'),
            ),

            const SizedBox(height: 100), // room above FAB
          ],
        ),
      ),

      // ── Bottom Button ─────────────────────────────────────────────────
      bottomNavigationBar: _buildBottomBar(rl),
    );
  }

  // ─── APP BAR ─────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(_RL rl) => AppBar(
    scrolledUnderElevation: 0,
    backgroundColor:  Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    title: const Text(
      'Product Details',
      style: TextStyle(
        color:      _T.textDark,
        fontSize:   18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    leading: Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _T.textDark, size: 18),
        ),
      ),
    ),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Divider(height: 1, color: Colors.grey.shade200),
    ),
  );

  // ─── IMAGE CAROUSEL ───────────────────────────────────────────────────────
  Widget _buildCarousel(_RL rl, List images) {
    return Padding(
      padding: EdgeInsets.fromLTRB(rl.hPad, 12, rl.hPad, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: rl.carouselH,
          width:  double.infinity,
          child: images.isEmpty
              ? Container(
            color: Colors.grey[200],
            child: const Center(
              child: Icon(Icons.image_not_supported,
                  size: 60, color: Colors.grey),
            ),
          )
              : PageView.builder(
            controller:  _pageController,
            itemCount:   images.length,
            onPageChanged: (i) =>
                setState(() => _currentImageIndex = i),
            itemBuilder: (_, i) => Image.network(
              images[i],
              fit:   BoxFit.cover,
              width: double.infinity,
              frameBuilder: (ctx, child, frame, _) {
                if (frame == null) {
                  return Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _T.purple),
                    ),
                  );
                }
                return child;
              },
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image,
                    size: 48, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── DOT INDICATORS ──────────────────────────────────────────────────────
  Widget _buildDots(int count) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _currentImageIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin:   const EdgeInsets.symmetric(horizontal: 3),
          width:    active ? 22 : 7,
          height:   5,
          decoration: BoxDecoration(
            color:        active ? _T.purple : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    ),
  );

  // ─── INFO CARD ────────────────────────────────────────────────────────────
  Widget _buildInfoCard(_RL rl) {
    final title     = widget.data['title']     ?? 'No title';
    final price     = widget.data['price'];
    final condition = widget.data['condition'] ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: rl.hPad),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDecor(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + condition badge on same row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize:   20,
                      fontWeight: FontWeight.w600,
                      color:      _T.textDark,
                      height:     1.25,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (condition.isNotEmpty) _conditionBadge(condition),
              ],
            ),
            const SizedBox(height: 14),

            // Price row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_T.purple, _T.deepPurple],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:      _T.purple.withOpacity(0.3),
                        blurRadius: 10,
                        offset:     const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    '₹ ${_formatPrice(price)}',
                    style: const TextStyle(
                      fontSize:   16,
                      fontWeight: FontWeight.w600,
                      color:      Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _conditionBadge(String condition) {
    Color bg, fg;
    IconData icon;
    switch (condition.toLowerCase()) {
      case 'new':
        bg   = const Color(0xFFE8F5E9);
        fg   = const Color(0xFF2E7D32);
        icon = Icons.fiber_new_rounded;
        break;
      case 'like new':
        bg   = const Color(0xFFE3F2FD);
        fg   = const Color(0xFF1565C0);
        icon = Icons.star_rounded;
        break;
      case 'good':
        bg   = const Color(0xFFFFF8E1);
        fg   = const Color(0xFFF57F17);
        icon = Icons.thumb_up_alt_rounded;
        break;
      default:
        bg   = const Color(0xFFF3E5F5);
        fg   = _T.purple;
        icon = Icons.check_circle_outline_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(condition,
            style: TextStyle(
                color:      fg,
                fontSize:   12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ─── META CARD (location, category, condition) ────────────────────────────
  Widget _buildMetaCard(_RL rl) {
    final location  = widget.data['location']  ?? '—';
    final category  = widget.data['category']  ?? '—';
    final condition = widget.data['condition'] ?? '—';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: rl.hPad),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: _cardDecor(),
        child: Column(
          children: [
            _metaRow(
              icon:  Icons.location_on_rounded,
              color: const Color(0xFFE53935),
              label: 'Location',
              value: location,
            ),
            _metaDivider(),
            _metaRow(
              icon:  Icons.category_rounded,
              color: _T.purple,
              label: 'Category',
              value: category,
            ),
            _metaDivider(),
            _metaRow(
              icon:  Icons.verified_rounded,
              color: _T.teal,
              label: 'Condition',
              value: condition,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width:  36,
            height: 36,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize:      11,
                        color:         _T.textLight,
                        fontWeight:    FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize:   14,
                        color:      _T.textDark,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaDivider() =>
      Divider(height: 1, thickness: 1, color: Colors.grey.shade100);

  // ─── DESCRIPTION CARD ─────────────────────────────────────────────────────
  Widget _buildDescriptionCard(_RL rl) {
    final desc = widget.data['description'] ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: rl.hPad),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: _cardDecor(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.notes_rounded, color: _T.purple, size: 18),
              SizedBox(width: 8),
              Text(
                'Description',
                style: TextStyle(
                  fontSize:      15,
                  fontWeight:    FontWeight.w700,
                  color:         _T.textDark,
                  letterSpacing: -0.2,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(
              desc.isEmpty ? 'No description provided.' : desc,
              textAlign: TextAlign.justify,
              style: const TextStyle(
                fontSize:   14,
                color:      _T.textMid,
                fontWeight: FontWeight.w400,
                height:     1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CARD DECORATION ─────────────────────────────────────────────────────
  BoxDecoration _cardDecor() => BoxDecoration(
    color:        _T.cardBg,
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color:      Colors.black.withOpacity(0.05),
        blurRadius: 16,
        offset:     const Offset(0, 4),
      ),
    ],
  );

  // ─── BOTTOM BAR ───────────────────────────────────────────────────────────
  Widget _buildBottomBar(_RL rl) => SafeArea(
    child: Container(
      padding: EdgeInsets.symmetric(
          horizontal: rl.hPad, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset:     const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width:  double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _isLoading
                ? LinearGradient(colors: [
              Colors.grey.shade400,
              Colors.grey.shade500,
            ])
                : const LinearGradient(
              colors: [Color(0xFFD84315), Color(0xFFBF360C)],
              begin:  Alignment.centerLeft,
              end:    Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isLoading
                ? []
                : [
              BoxShadow(
                color:      const Color(0xFFD84315).withOpacity(0.35),
                blurRadius: 14,
                offset:     const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _sellToCompany,
            icon: _isLoading
                ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.storefront_outlined,
                color: Colors.white, size: 22),
            label: Text(
              _isLoading ? 'Opening chat...' : 'Swap to Sell Company',
              style: const TextStyle(
                fontWeight:    FontWeight.w600,
                fontSize:      16,
                color:         Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:         Colors.transparent,
              shadowColor:             Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final num p     = price is num ? price : num.tryParse(price.toString()) ?? 0;
    final String s  = p.toStringAsFixed(0);
    if (s.length <= 3) return s;
    final String lastThree  = s.substring(s.length - 3);
    final String rest       = s.substring(0, s.length - 3);
    final String withCommas =
    rest.replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (m) => ',');
    return '$withCommas,$lastThree';
  }
}