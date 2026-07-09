import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_product_page.dart';
import 'product_detail_page.dart';

class MyProductsPage extends StatelessWidget {
  const MyProductsPage({super.key});

  Future<void> _confirmDelete(BuildContext context, String docId) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 360;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isSmall ? 16 : 24,
            20,
            isSmall ? 16 : 24,
            isSmall ? 24 : 36,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade400, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Product?',
                style: TextStyle(
                    fontSize: isSmall ? 16 : 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone. The product will be permanently removed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: isSmall ? 12 : 13,
                    color: Colors.grey.shade500,
                    height: 1.5),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: isSmall ? 12 : 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmall ? 13 : 14,
                              color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        padding: EdgeInsets.symmetric(
                            vertical: isSmall ? 12 : 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text('Delete',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: isSmall ? 13 : 14,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    void showSuccessSnack(String message) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(seconds: 2),
          ),
        );
    }

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('UserProductList')
          .doc(docId)
          .delete();
      showSuccessSnack("Product deleted successfully!");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isSmall = screenWidth < 360;

    final crossAxisCount = isTablet ? 3 : (isSmall ? 1 : 2);
    final hPadding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 16.0 : 12.0;

    // Taller aspect ratio gives the info + button row more room
    final aspectRatio = isSmall ? 0.72 : (isTablet ? 0.58 : 0.56);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "My Products",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.black, size: 18),
            onPressed: () {
              Navigator.pop(context);
            }
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('UserProductList')
            .where('userId', isEqualTo: user!.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6A00FF)),
            );
          }

          final products = snapshot.data!.docs;

          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: isSmall ? 52 : 64,
                        color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No products uploaded yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: isSmall ? 14 : 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
                hPadding, hPadding, hPadding, hPadding + 8),
            itemCount: products.length,
            // ── In MyProductsPage, update gridDelegate: ──────────────────
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: isSmall ? 0.75 : (isTablet ? 0.72 : 0.70),
            ),
            itemBuilder: (context, index) {
              final doc = products[index];
              final data = doc.data() as Map<String, dynamic>;
              final images = List<String>.from(data['images'] ?? []);

              return _ProductCard(
                doc: doc,
                data: data,
                images: images,
                onView: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(
                      productId: doc.id,
                      data: data,
                    ),
                  ),
                ),
                onEdit: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProductPage(
                      productId: doc.id,
                      data: data,
                    ),
                  ),
                ),
                onDelete: () => _confirmDelete(context, doc.id),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Redesigned card widget
// ─────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final List<String> images;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.doc,
    required this.data,
    required this.images,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 360;
    final isTablet = screenWidth >= 600;

    final titleFontSize = isSmall ? 13.0 : (isTablet ? 15.0 : 14.0);
    final priceFontSize = isSmall ? 13.0 : (isTablet ? 15.0 : 14.0);

    return GestureDetector(
      onTap: onView,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [

            // ── Image with padding ─────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFFEEEEEE), // always solid bg
                        child: images.isNotEmpty
                            ? Image.network(
                          images[0],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Colors.grey.shade400,
                              size: isSmall ? 24 : 30,
                            ),
                          ),
                        )
                            : Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                            size: isSmall ? 24 : 30,
                          ),
                        ),
                      ),
                    ),

                    // Delete button — top right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 17,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Info + actions (fixed height, no Spacer) ───────
            Padding(
              padding: EdgeInsets.fromLTRB(
                isSmall ? 10 : 12,
                8,
                isSmall ? 10 : 12,
                isSmall ? 10 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // wraps tightly
                children: [
                  // Title
                  Text(
                    data['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: titleFontSize,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Price + Condition pill
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '₹ ${data['price'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: priceFontSize,
                            color: const Color(0xFF6A00FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if ((data['condition'] ?? '').toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0E8FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            data['condition'],
                            style: TextStyle(
                              fontSize: isSmall ? 10 : 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6A00FF),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // View | Edit buttons
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'View',
                          icon: Icons.visibility_outlined,
                          foreground: const Color(0xFF6A00FF),
                          background: const Color(0xFFF0E8FF),
                          onTap: onView,
                          isSmall: isSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ActionButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          foreground: const Color(0xFF0055CC),
                          background: const Color(0xFFDEEAFF),
                          onTap: onEdit,
                          isSmall: isSmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// Labelled action button (View / Edit)
// ─────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;
  final bool isSmall;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.onTap,
    required this.isSmall,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: foreground.withOpacity(0.12),
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: isSmall ? 7 : 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isSmall ? 13 : 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmall ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}