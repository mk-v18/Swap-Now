import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/Advertisement/location_ad.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../chats/chatscreen.dart';
import '../chats/chatservice.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
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
// RESPONSIVE HELPER
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
  double get swapThumb  => isDesktop ? 72 : (isTablet ? 64 : 58);
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────
class UserProductDetailsPage extends StatefulWidget {
  final Map<String, dynamic> productData;
  const UserProductDetailsPage({super.key, required this.productData});

  @override
  State<UserProductDetailsPage> createState() => _UserProductDetailsPageState();
}

class _UserProductDetailsPageState extends State<UserProductDetailsPage> {
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();

  String? _sellerName;
  String? _sellerImage;
  bool    _sellerLoaded   = false;
  bool    _isMessaging    = false;

  List<Map<String, dynamic>> _myProducts = [];
  String? _selectedSwapProductId;
  bool _myProductsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSeller();
  }

  void _loadSeller() {
    final sellerId = widget.productData['userId'];
    if (sellerId == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(sellerId as String)
        .get()
        .then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _sellerName   = d['name']         ?? 'Seller';
          _sellerImage  = d['profileImage'] ?? '';
          _sellerLoaded = true;
        });
      }
    });
  }

  Future<void> _loadMyProducts() async {
    if (_myProductsLoaded) return;
    final uid  = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('UserProductList')
        .where('userId', isEqualTo: uid)
        .get();
    if (mounted) {
      setState(() {
        _myProducts       = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _myProductsLoaded = true;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rl     = _RL.of(context);
    final images = (widget.productData['images'] as List?) ?? [];

    return Scaffold(
      backgroundColor: Color(0xFFFFFFFF),
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

      // ── Swap Button ───────────────────────────────────────────────────
      bottomNavigationBar: _buildBottomBar(rl),
    );
  }

  // ─── APP BAR ─────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(_RL rl) => AppBar(
    scrolledUnderElevation: 0,
    backgroundColor:  Color(0xFFFFFFFF),
    surfaceTintColor: Color(0xFFFFFFFF),
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
    final title     = widget.productData['title']     ?? 'No title';
    final price     = widget.productData['price'];
    final condition = widget.productData['condition'] ?? '';

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
                if (condition.isNotEmpty)
                  _conditionBadge(condition),
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
                      colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:      const Color(0xFF5800B3).withOpacity(0.3),
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
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        _T.tealLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.swap_horiz_rounded,
                          color: _T.teal, size: 15),
                      SizedBox(width: 4),
                      Text(
                        'Swap available',
                        style: TextStyle(
                          color:      _T.teal,
                          fontSize:   11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
    final location = widget.productData['location'] ?? '—';
    final category = widget.productData['category'] ?? '—';
    final condition = widget.productData['condition'] ?? '—';

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
                        fontSize:   11,
                        color:      _T.textLight,
                        fontWeight: FontWeight.w600,
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

  Widget _metaDivider() => Divider(
      height: 1, thickness: 1, color: Colors.grey.shade100);

  // ─── DESCRIPTION CARD ─────────────────────────────────────────────────────
  Widget _buildDescriptionCard(_RL rl) {
    final desc = widget.productData['description'] ?? '';

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
                  fontSize:   15,
                  fontWeight: FontWeight.w700,
                  color:      _T.textDark,
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

  // ─── BOTTOM BAR — Swap only ───────────────────────────────────────────────
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
            gradient: _isMessaging
                ? LinearGradient(colors: [
              _T.teal.withOpacity(0.5),
              _T.teal.withOpacity(0.4),
            ])
                : const LinearGradient(
              colors: [Color(0xFF5800B3), Color(0xFF26004D)],
              begin:  Alignment.centerLeft,
              end:    Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isMessaging
                ? []
                : [
              BoxShadow(
                color:      _T.teal.withOpacity(0.35),
                blurRadius: 14,
                offset:     const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _isMessaging ? null : _initiateSwap,
            icon: _isMessaging
                ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.swap_horiz_rounded,
                color: Colors.white, size: 22),
            label: Text(
              _isMessaging ? 'Opening chat...' : 'Message',
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

  // ─── INITIATE SWAP (guard → swap sheet → safety → chat) ──────────────────
  Future<void> _initiateSwap() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnack('Please login to propose a swap.');
      return;
    }
    final sellerId = widget.productData['userId'] as String?;
    if (sellerId == null) {
      _showSnack('Seller info unavailable.');
      return;
    }
    if (sellerId == currentUser.uid) {
      _showSnack("You can't swap with your own listing.");
      return;
    }
    await _showSwapSheet();
  }

  // ─── SWAP PRODUCT SELECTOR ────────────────────────────────────────────────
  Future<void> _showSwapSheet() async {
    await _loadMyProducts();
    if (!mounted) return;

    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        return _SwapSheet(
          myProducts:   _myProducts,
          selectedId:   _selectedSwapProductId,   // ← single String?
          onToggle: (id) {
            setSheet(() {
              _selectedSwapProductId =
              _selectedSwapProductId == id ? null : id; // deselect on re-tap
            });
          },
          onConfirm: () {
            Navigator.pop(ctx);
            if (_selectedSwapProductId == null) return; // guard
            final selected = _myProducts
                .where((p) => p['id'] == _selectedSwapProductId)
                .toList();
            _showSafetyThenChat(selected);
          },
        );
      }),
    );
  }

  // ─── SAFETY SHEET → CHAT ─────────────────────────────────────────────────
  Future<void> _showSafetyThenChat(
      List<Map<String, dynamic>> swapProducts) async {
    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      isDismissible:      true,
      builder: (_) => _SafetyCautionSheet(
        onConfirm: () {
          Navigator.pop(context);
          _openChat(swapProducts);
        },
      ),
    );
  }

  // ─── OPEN CHAT ────────────────────────────────────────────────────────────
  Future<void> _openChat(List<Map<String, dynamic>> swapProducts) async {
    setState(() => _isMessaging = true);
    final sellerId    = widget.productData['userId'] as String;
    final currentUser = FirebaseAuth.instance.currentUser!;
    try {
      if (!_sellerLoaded) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(sellerId)
            .get();
        if (!doc.exists) { _showSnack('Seller not found.'); return; }
        final d   = doc.data()!;
        _sellerName   = d['name']         ?? 'Seller';
        _sellerImage  = d['profileImage'] ?? '';
        _sellerLoaded = true;
      }

      final chatService = ChatService();
      final chatId = await chatService.getOrCreateChat(
          currentUser.uid, sellerId);

      final swapForDb = swapProducts.map((p) => {
        'id':          p['id'],
        'title':       p['title']       ?? '',
        'price':       p['price']       ?? '',
        'images':      (p['images'] as List?) ?? [],
        'condition':   p['condition']   ?? '',
        'category':    p['category']    ?? '',
        'location':    p['location']    ?? '',
        'description': p['description'] ?? '',
      }).toList();

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .set({
        'intent': {
          'type':          'swap',
          'listedProduct': {
            'title':  widget.productData['title']  ?? '',
            'price':  widget.productData['price']  ?? '',
            'images': ((widget.productData['images'] as List?)
                ?.take(1)
                .toList()) ??
                [],
          },
          'swapProducts': swapForDb,
          'updatedAt':    FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId:        chatId,
            receiverId:    sellerId,
            receiverName:  _sellerName!,
            receiverImage: _sellerImage!,
          ),
        ),
      );
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isMessaging = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final num p    = price is num ? price : num.tryParse(price.toString()) ?? 0;
    final String s = p.toStringAsFixed(0);
    if (s.length <= 3) return s;
    final last3    = s.substring(s.length - 3);
    final rest     = s.substring(0, s.length - 3);
    final commas   = rest.replaceAllMapped(
        RegExp(r'\B(?=(\d{2})+(?!\d))'), (m) => ',');
    return '$commas,$last3';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SWAP SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _SwapSheet extends StatelessWidget {
  final List<Map<String, dynamic>> myProducts;
  final String?               selectedId;      // ← single nullable id
  final void Function(String) onToggle;
  final VoidCallback          onConfirm;

  const _SwapSheet({
    required this.myProducts,
    required this.selectedId,
    required this.onToggle,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final rl       = _RL.of(context);
    final hasSelection = selectedId != null;

    return DraggableScrollableSheet(
      initialChildSize: rl.isMobile ? 0.72 : 0.62,
      minChildSize:     0.4,
      maxChildSize:     rl.sheetMax,
      expand:           false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 14, bottom: 4),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(rl.hPad, 12, rl.hPad, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        _T.lightPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.swap_horiz_rounded,
                    color: _T.purple, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose what to swap',
                        style: TextStyle(
                            fontSize:   17,
                            fontWeight: FontWeight.w700,
                            color:      _T.textDark)),
                    SizedBox(height: 2),
                    Text('Pick one product to offer',
                        style: TextStyle(fontSize: 12, color: _T.textLight)),
                  ],
                ),
              ),
            ]),
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: myProducts.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                        color: _T.lightPurple, shape: BoxShape.circle),
                    child: const Icon(Icons.inventory_2_outlined,
                        size: 36, color: _T.purple),
                  ),
                  const SizedBox(height: 12),
                  const Text('No products listed yet',
                      style: TextStyle(
                          color:      _T.textMid,
                          fontSize:   15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('List a product first to propose a swap',
                      style: TextStyle(
                          color: _T.textLight, fontSize: 12)),
                ],
              ),
            )
                : ListView.separated(
              controller:  scroll,
              padding:     EdgeInsets.symmetric(
                  horizontal: rl.hPad, vertical: 4),
              itemCount:   myProducts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p        = myProducts[i];
                final id       = p['id'] as String;
                final selected = selectedId == id;          // ← single compare
                final imgs     = (p['images'] as List?) ?? [];
                final imgUrl   = imgs.isNotEmpty ? imgs[0] as String : null;

                return GestureDetector(
                  onTap: () => onToggle(id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:  const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? _T.lightPurple : Colors.grey[50],
                      border: Border.all(
                        color: selected ? _T.purple : Colors.grey.shade200,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width:  rl.swapThumb,
                          height: rl.swapThumb,
                          color:  Colors.grey[200],
                          child: imgUrl != null
                              ? Image.network(imgUrl, fit: BoxFit.cover)
                              : const Icon(Icons.image_not_supported,
                              color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['title'] ?? 'Product',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize:   14,
                                    fontWeight: FontWeight.w700,
                                    color:      _T.textDark)),
                            const SizedBox(height: 4),
                            Text('₹ ${p['price'] ?? '—'}',
                                style: const TextStyle(
                                    fontSize:   13,
                                    color:      _T.purple,
                                    fontWeight: FontWeight.w700)),
                            if ((p['condition'] ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:        _T.lightPurple,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(p['condition'],
                                      style: const TextStyle(
                                          fontSize:   10,
                                          color:      _T.purple,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Radio-style indicator (purple)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: selected ? _T.purple : Colors.transparent,
                          border: Border.all(
                              color: selected
                                  ? _T.purple
                                  : Colors.grey.shade400,
                              width: 2),
                          borderRadius: BorderRadius.circular(13), // circle = radio
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16)
                            : null,
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),

          // Confirm button — disabled until one item selected
          Padding(
            padding: EdgeInsets.fromLTRB(
                rl.hPad, 12, rl.hPad,
                MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width:  double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: (!hasSelection || myProducts.isEmpty)
                      ? LinearGradient(colors: [
                    Colors.grey.shade400,
                    Colors.grey.shade500,
                  ])
                      : const LinearGradient(
                    colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: (!hasSelection || myProducts.isEmpty)
                      ? []
                      : [
                    BoxShadow(
                      color:      _T.purple.withOpacity(0.3),
                      blurRadius: 12,
                      offset:     const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: (hasSelection && myProducts.isNotEmpty)
                      ? onConfirm
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded,
                      color: Colors.white, size: 20),
                  label: Text(
                    hasSelection ? 'Swap 1 item' : 'Select an item to swap',
                    style: const TextStyle(
                        color:      Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize:   15),
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
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAFETY CAUTION SHEET
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// SAFETY CAUTION SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _SafetyCautionSheet extends StatefulWidget {
  final VoidCallback onConfirm;
  const _SafetyCautionSheet({required this.onConfirm});

  @override
  State<_SafetyCautionSheet> createState() => _SafetyCautionSheetState();
}

class _SafetyCautionSheetState extends State<_SafetyCautionSheet> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final rl = _RL.of(context);

    return DraggableScrollableSheet(
      initialChildSize: rl.isMobile ? 0.82 : 0.72,
      minChildSize:     0.4,
      maxChildSize:     rl.sheetMax,
      expand:           false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // ── Handle ────────────────────────────────────────────────────
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 14, bottom: 0),
              decoration: BoxDecoration(
                  color:        Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),

            // ── Scrollable body ───────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(
                    rl.hPad, 20, rl.hPad, 0),
                children: [
                  // Header icon + title
                  Center(
                    child: Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B1FA2), Color(0xFF4A148C)],
                          begin:  Alignment.topLeft,
                          end:    Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color:      _T.purple.withOpacity(0.30),
                            blurRadius: 14,
                            offset:     const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'Before you swap',
                      style: TextStyle(
                          fontSize:      20,
                          fontWeight:    FontWeight.w800,
                          color:         _T.textDark,
                          letterSpacing: -0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'SwapNow keeps it safe — here\'s how',
                      style: TextStyle(
                          fontSize: 12.5,
                          color:    Colors.grey[500],
                          height:   1.4),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Rules ───────────────────────────────────────────────
                  _rule(
                    number: '1',
                    icon:   Icons.currency_rupee_rounded,
                    iconBg: const Color(0xFFFCEBEB),
                    iconFg: const Color(0xFFC62828),
                    title:  'Exchanges only — no money',
                    body:   'SwapNow is for item-for-item swaps. Never pay or ask for money.',
                  ),
                  const SizedBox(height: 10),
                  _rule(
                    number: '2',
                    icon:   Icons.search_rounded,
                    iconBg: const Color(0xFFE8EAF6),
                    iconFg: const Color(0xFF283593),
                    title:  'Verify before you exchange',
                    body:   'Check the item in person or via video call before agreeing to swap.',
                  ),
                  const SizedBox(height: 10),
                  _rule(
                    number: '3',
                    icon:   Icons.store_mall_directory_outlined,
                    iconBg: const Color(0xFFE0F2F1),
                    iconFg: const Color(0xFF00695C),
                    title:  'Meet in a safe public place',
                    body:   'Choose a busy, well-lit spot. Never meet alone in an unknown location.',
                  ),
                  const SizedBox(height: 10),
                  _rule(
                    number: '4',
                    icon:   Icons.info_outline_rounded,
                    iconBg: const Color(0xFFFFF8E1),
                    iconFg: const Color(0xFFF57F17),
                    title:  'SwapNow is a platform, not a guarantor',
                    body:   'We connect users but aren\'t responsible for exchanges or disputes.',
                  ),
                  const SizedBox(height: 22),

                  // ── Agree row ───────────────────────────────────────────
                  GestureDetector(
                    onTap: () => setState(() => _agreed = !_agreed),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: _agreed
                            ? _T.lightPurple
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _agreed
                              ? _T.purple.withOpacity(0.45)
                              : Colors.grey.shade300,
                          width: _agreed ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: _agreed ? _T.purple : Colors.transparent,
                            border: Border.all(
                                color: _agreed ? _T.purple : Colors.grey,
                                width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _agreed
                              ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'I\'ve read these rules and want to continue',
                            style: TextStyle(
                                fontSize:   13,
                                fontWeight: FontWeight.w600,
                                color:      _T.textDark,
                                height:     1.35),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Sticky bottom button ──────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                  rl.hPad, 12, rl.hPad,
                  MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset:     const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width:  double.infinity,
                height: 52,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: _agreed
                        ? const LinearGradient(
                      colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                      begin:  Alignment.centerLeft,
                      end:    Alignment.centerRight,
                    )
                        : LinearGradient(colors: [
                      Colors.grey.shade300,
                      Colors.grey.shade400,
                    ]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _agreed
                        ? [
                      BoxShadow(
                        color:      _T.purple.withOpacity(0.35),
                        blurRadius: 14,
                        offset:     const Offset(0, 6),
                      ),
                    ]
                        : [],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _agreed ? widget.onConfirm : null,
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white, size: 18),
                    label: const Text(
                      'Start chatting',
                      style: TextStyle(
                          color:         Colors.white,
                          fontSize:      15,
                          fontWeight:    FontWeight.w600,
                          letterSpacing: 0.2),
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
          ],
        ),
      ),
    );
  }

  Widget _rule({
    required String   number,
    required IconData icon,
    required Color    iconBg,
    required Color    iconFg,
    required String   title,
    required String   body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: Colors.grey.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset:     const Offset(0, 3),
          ),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Numbered icon
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconFg, size: 20),
            ),
            Positioned(
              top: -5, right: -5,
              child: Container(
                width: 17, height: 17,
                decoration: BoxDecoration(
                  color:  _T.purple,
                  shape:  BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   9,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        // Text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize:   13.5,
                      fontWeight: FontWeight.w700,
                      color:      _T.textDark,
                      height:     1.2)),
              const SizedBox(height: 4),
              Text(body,
                  style: TextStyle(
                      fontSize: 12,
                      color:    Colors.grey[600],
                      height:   1.5)),
            ],
          ),
        ),
      ]),
    );
  }
}