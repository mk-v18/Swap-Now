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

    const Color purple = Color(0xFF6A00FF);
    const Color danger = Color(0xFFE0392C);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isSmall ? 20 : 28,
            14,
            isSmall ? 20 : 28,
            isSmall ? 20 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),

              // Icon badge — soft ring instead of flat shadowed circle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: danger.withOpacity(0.18),
                    width: 1.2,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: danger.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      color: danger, size: 30),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                'Delete Product?',
                style: TextStyle(
                  fontSize: isSmall ? 17 : 19,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A1A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'This action cannot be undone. The product\nwill be permanently removed from listings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmall ? 12.5 : 13.5,
                  color: Colors.grey.shade500,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: isSmall ? 46 : 50,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmall ? 13.5 : 14.5,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: isSmall ? 46 : 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.delete_outline_rounded, size: 17),
                            const SizedBox(width: 6),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: isSmall ? 13.5 : 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
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
              // NEW: once a swap for this listing is marked successful, the
              // onSwapCompleted Cloud Function sets status: 'exchanged' on
              // this doc. Once exchanged, the owner can only View it —
              // Edit/Delete no longer make sense for a listing that's
              // already been swapped away.
              final isExchanged = (data['status'] ?? '') == 'exchanged';

              return _ProductCard(
                doc: doc,
                data: data,
                images: images,
                isExchanged: isExchanged,
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
  final bool isExchanged;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.doc,
    required this.data,
    required this.images,
    required this.isExchanged,
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

    const Color borderColor = Color(0xFFECEAFF);
    const Color purple = Color(0xFF6A00FF);
    const Color exchangedColor = Color(0xFF00796B);

    return GestureDetector(
      onTap: onView,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [

            // ── Image with padding (tightened) ─────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFFEEEEEE), // always solid bg
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            images.isNotEmpty
                                ? Image.network(
                              images[0],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              // NOTE: no color/colorBlendMode here anymore — that combo
                              // was causing the image to render upside-down on some
                              // devices (a GPU shader compositing issue with blended
                              // Image widgets). Dimming is now done via a plain overlay
                              // below instead, which avoids the bug entirely.
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

                            // NEW: dim overlay for exchanged listings — replaces the old
                            // color/colorBlendMode tint on Image.network.
                            if (isExchanged)
                              Container(color: Colors.black.withOpacity(0.35)),
                          ],
                        ),
                      ),
                    ),

                    // Delete button — top right (minimized). Hidden once
                    // exchanged: a swapped-away listing shouldn't be
                    // editable/deletable, only viewable as a record.
                    if (!isExchanged)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: borderColor,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 15,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // NEW: "Exchanged" pill replaces the condition pill
                    // once the swap is successful, so the owner can tell
                    // at a glance why Edit/Delete are gone.
                    if (isExchanged)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 11, color: exchangedColor),
                              const SizedBox(width: 3),
                              Text(
                                'Exchanged',
                                style: TextStyle(
                                  fontSize: isSmall ? 8 : 10,
                                  fontWeight: FontWeight.w600,
                                  color: exchangedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if ((data['condition'] ?? '').toString().isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            data['condition'],
                            style: TextStyle(
                              fontSize: isSmall ? 8 : 10,
                              fontWeight: FontWeight.w600,
                              color: purple,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Info ─────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                isSmall ? 10 : 12,
                8,
                isSmall ? 10 : 12,
                0,
              ),
              child: Text(
                data['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: titleFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),

            // ── Action row — attached footer ─────────────────────
            // NEW: once exchanged, only "View" is shown (full width, no
            // divider) — Edit/Delete are removed rather than just
            // disabled, since they no longer apply to this listing.
            Padding(
              padding: EdgeInsets.fromLTRB(
                isSmall ? 10 : 12,
                8,
                isSmall ? 10 : 12,
                isSmall ? 8 : 10,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: IntrinsicHeight(
                  child: isExchanged
                      ? Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'View',
                          icon: Icons.visibility_outlined,
                          color: purple,
                          onTap: onView,
                          isSmall: isSmall,
                        ),
                      ),
                    ],
                  )
                      : Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: 'View',
                          icon: Icons.visibility_outlined,
                          color: purple,
                          onTap: onView,
                          isSmall: isSmall,
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        indent: 8,
                        endIndent: 8,
                        color: borderColor,
                      ),
                      Expanded(
                        child: _ActionButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          color: const Color(0xFF0055CC),
                          onTap: onEdit,
                          isSmall: isSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Flat, icon+label action button used inside the split footer
// ─────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isSmall;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.isSmall,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: isSmall ? 8 : 9, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isSmall ? 14 : 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmall ? 11 : 12,
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
}